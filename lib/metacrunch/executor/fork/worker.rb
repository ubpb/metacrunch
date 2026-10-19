# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # The loop of one worker process: opens the step callables, reads
      # batches from its input, pushes them through a Processor and writes
      # the results to its output (Frame, Dump). Runs in the forked child;
      # tests drive #run in-process through pipes.
      class Worker

        # Collects what leaves the chain as events of the current frame.
        class BatchOutlet

          # deliver, reject: false if the pipeline has no sink or no rejects
          # sink; those records are then not sent at all.
          def initialize(events, deliver:, reject:)
            @events = events
            @deliver = deliver
            @reject = reject
          end

          def deliver(record, ctx)
            @events << [:deliver, record, ctx.to_state] if @deliver
          end

          def reject(record, ctx)
            @events << [:reject, record, ctx.to_state] if @reject
          end

          # Always sent: the parent counts failures for max_failures.
          def fail(record, ctx)
            @events << [:fail, record, ctx.to_state]
          end

        end

        # The log device of the worker's logger: every formatted line becomes
        # an event, so the parent writes it in order with the records.
        class LogBuffer

          def initialize(events)
            @events = events
          end

          def write(line)
            @events << [:log, line]
          end

          def close = nil

        end

        # Signals whose handlers the child resets: a program that runs jobs
        # with workers may trap them, and its handlers must not run in a
        # worker.
        HOST_SIGNALS = ["INT", "TERM", "HUP", "QUIT", "USR1", "USR2", "CHLD"].freeze

        # Runs a worker in the forked child. inherited: the parent's pipe ends
        # the child must close. The process ends without the at_exit
        # handlers, finalizers and write buffers inherited from the parent,
        # also when a second signal arrives while it ends. A signal ends it by
        # that signal. The fork happens under handle_interrupt(Object =>
        # :never); interrupts are allowed again only inside the begin below,
        # so a signal pending since the fork ends the process here, too.
        def self.main(pipeline, input, output, inherited: [])
          status = 1
          begin
            Thread.handle_interrupt(Object => :immediate) do
              HOST_SIGNALS.each { Signal.trap(it, "DEFAULT") }
              inherited.each(&:close)
              new(pipeline).run(input, output)
            end
            status = 0
          rescue SignalException => e
            Signal.trap(e.signo, "SYSTEM_DEFAULT")
            Process.kill(e.signo, Process.pid)
          rescue Exception # rubocop:disable Lint/RescueException
            status = 1
          ensure
            Process.exit!(status)
          end
        end

        def initialize(pipeline)
          @pipeline = pipeline
          @events = []
          @stats = StatsCollector.new(pipeline.steps.map(&:name), profile: pipeline.profile)
          outlet = BatchOutlet.new(@events, deliver: !pipeline.sink.nil?, reject: !pipeline.rejects.nil?)
          @processor = Processor.new(pipeline, stats: @stats, outlet:)
        end

        # Sends :ready (or the error of open), the result of every batch and
        # :done (with the error of close). Returns after a batch that ended
        # with an error. A signal, also an Interrupt raised by a step, closes
        # the step callables and is raised again.
        def run(input, output)
          @output = output
          redirect_logger
          return unless ready?

          error = process_batches(input)
          close_error = close_steps
          send_frame(:done, error: close_error) unless error
        rescue SignalException
          @processor.close
          raise
        end

        private

        # Logger#reopen with an object that has write and close is public
        # Logger API. Other loggers write directly from the worker.
        def redirect_logger
          logger = @pipeline.logger
          logger.reopen(LogBuffer.new(@events)) if logger.is_a?(::Logger)
        end

        # Opens the step callables and sends :ready, with the exception that
        # open raised, also an exit, as inline. Signals pass.
        def ready?
          @processor.open
          send_frame(:ready)
          true
        rescue SignalException
          raise
        rescue Exception => e # rubocop:disable Lint/RescueException
          close_steps
          send_frame(:ready, error: e)
          false
        end

        # Closes the step callables and returns the first error, also an exit,
        # which the parent raises as inline. Signals pass.
        def close_steps
          @processor.close
        rescue SignalException
          raise
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        end

        # Returns the error that ended a batch, or nil at the end of the
        # input. After an error the steps are closed before the batch's frame
        # goes out, so their log lines reach the parent, as inline; the parent
        # reads no frame of this worker after that one.
        def process_batches(input)
          while (batch = Frame.read(input))
            positions, records = batch
            error = process(positions, records)
            close_steps if error
            error = send_frame(:batch, error:)
            return error if error
          end
          nil
        end

        # records: one Marshal dump per record (see Run#add). Returns the
        # exception that stopped the batch, or nil. Signals pass.
        def process(positions, records)
          positions.each_with_index do |position, index|
            @processor.call(load_record(records[index], position), position)
          end
          nil
        rescue SignalException
          raise
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        end

        # Records come only from the parent. A record of a class this process
        # does not know (Marshal raises ArgumentError) comes from a library
        # the parent loaded after the fork.
        def load_record(data, position)
          Marshal.load(data) # rubocop:disable Security/MarshalLoad
        rescue ArgumentError => e
          raise Error, "record at position #{position} cannot be read in a worker (#{e.message}); " \
                       "with --workers, require libraries at job level, not while the source reads"
        end

        # Writes a frame and clears the events. A :batch frame carries what
        # the batch counted. Returns the frame's error, which Dump.frame sets
        # if a record could not be dumped.
        def send_frame(type, error: nil)
          stats = type == :batch ? @stats.take : nil
          data, error = Dump.frame({type:, events: @events, stats:, error:})
          Frame.write(@output, data)
          @events.clear
          error
        end

      end
    end
  end
end
