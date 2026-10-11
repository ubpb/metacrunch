# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # One run of the fork executor: forks the workers, waits until they
      # opened their steps, feeds them batches from a thread and applies
      # their results in order through the outlet. Stops the workers in any
      # case.
      class Run

        # The parent's side of a worker: its number (from 1), its pid, the
        # pipe it reads batches from (input), the pipe it writes frames to
        # (output) and its exit status once reaped.
        Handle = Struct.new(:number, :pid, :input, :output, :status) do
          def close
            [input, output].each { it.close unless it.closed? }
          end
        end

        INTERRUPT = Signal.list.fetch("INT")
        TERMINATE = Signal.list.fetch("TERM")

        def initialize(pipeline, workers:, batch_size:, stop_timeout:, stats:, outlet:, select:)
          @pipeline = pipeline
          @workers = workers
          @batch_size = batch_size
          @stop_timeout = stop_timeout
          @stats = stats
          @outlet = outlet
          @select = select
          @handles = []
          @feeder = nil
          @finished = false
        end

        def call
          start_workers
          @handles.each { raise_error(receive(it)) }
          @feeder = Thread.new { feed }
          apply_results
          @finished = true
        ensure
          stop
        end

        private

        def start_workers
          Process.warmup
          @workers.times { @handles << spawn(@handles.size + 1) }
          @pipeline.logger.debug { "started #{@workers} workers (pids #{@handles.map(&:pid).join(", ")})" }
        end

        # The child closes the parent's ends of its own pipes and of the
        # pipes of the workers started before it: a worker sees the end of
        # its input only when no other process holds the writing end.
        def spawn(number)
          input, feed = IO.pipe
          results, output = IO.pipe
          [input, feed, results, output].each(&:binmode)
          pid = Process.fork do
            [feed, results, *@handles.flat_map { [it.input, it.output] }].each(&:close)
            Worker.main(@pipeline, input, output)
          end
          input.close
          output.close
          Handle.new(number, pid, feed, results)
        end

        # Runs in the feeder thread: reads the source and sends batch k to
        # worker k mod N, then closes the input of every worker. Returns the
        # exception that ended the source, or nil.
        def feed
          Thread.current.report_on_exception = false
          numbered_records.each_slice(@batch_size).with_index do |slice, batch|
            break unless send_batch(@handles[batch % @workers], slice)
          end
          nil
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        ensure
          @handles.each { it.input.close unless it.input.closed? }
        end

        # The selected source records as [position, record] pairs.
        def numbered_records
          Enumerator.new do |yielder|
            Inline.each_record(@pipeline.source, limit: @pipeline.limit, select: @select) do |record, position|
              yielder << [position, record]
            end
          end
        end

        # Returns false if the worker is gone: it ended after an error, which
        # the main thread reports when it reaches that batch.
        def send_batch(handle, slice)
          Frame.write(handle.input, Marshal.dump(slice.transpose))
          true
        rescue Errno::EPIPE
          false
        end

        # Applies batch k from worker k mod N until a worker sends :done
        # instead: then no batch is left, and the others send :done too.
        def apply_results
          batch = 0
          loop do
            handle = @handles[batch % @workers]
            frame = receive(handle)
            return finish(handle, frame) if frame[:type] == :done

            raise_error(frame)
            batch += 1
          end
        end

        # Raises the error of the source, else the first error of closing.
        def finish(last, frame)
          frames = [frame, *(@handles - [last]).map { receive(it) }]
          error = @feeder.value || frames.filter_map { it[:error] }.first
          raise error if error
        end

        # Reads the next frame of a worker, adds its stats and applies its
        # events. Returns the frame.
        def receive(handle)
          frame = read(handle)
          @stats.absorb(frame[:stats]) if frame[:stats]
          frame[:events].each { apply(it) }
          frame
        end

        def apply(event)
          return @pipeline.logger << event.last if event.first == :log

          kind, record, state = event
          ctx = Context.from_state(state, logger: @pipeline.logger)
          case kind
          when :deliver then @outlet.deliver(record, ctx)
          when :reject then @outlet.reject(record, ctx)
          else @outlet.fail(record, ctx)
          end
        end

        def raise_error(frame)
          raise frame[:error] if frame[:error]
        end

        # A worker that closed its output without a whole frame has ended.
        def read(handle)
          Frame.read(handle.output) || ended(handle)
        rescue Frame::Truncated
          ended(handle)
        end

        # Raises the signal the worker ended by (SIGINT, SIGTERM), as if this
        # process had got it, else an Error.
        def ended(handle)
          status = reap(handle)
          raise Interrupt if status.termsig == INTERRUPT
          raise SignalException, TERMINATE if status.termsig == TERMINATE

          raise Error, "worker #{handle.number} (pid #{handle.pid}) ended unexpectedly"
        end

        def reap(handle)
          handle.status ||= Process.waitpid2(handle.pid).last
        end

        # Ends the feeder and the workers. After a normal end the workers have
        # ended already and are only reaped; otherwise they get SIGTERM.
        def stop
          @feeder&.kill&.join
          @handles.each(&:close)
          @handles.each { terminate(it) } unless @finished
          @handles.each do |handle|
            reap(handle)
            @pipeline.logger.debug { "worker #{handle.number} (pid #{handle.pid}) ended: #{handle.status}" }
          end
        end

        def terminate(handle)
          Process.kill("TERM", handle.pid) unless handle.status
        rescue Errno::ESRCH
          nil
        end

      end
    end
  end
end
