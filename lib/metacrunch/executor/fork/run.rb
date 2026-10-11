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
          @workers.times do
            # A signal that arrives during the fork is raised once the worker
            # is tracked, so stop ends it.
            Thread.handle_interrupt(Object => :never) { @handles << spawn(@handles.size + 1) }
          end
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
            inherited = [feed, results, *@handles.flat_map { [it.input, it.output] }]
            Thread.handle_interrupt(Object => :immediate) { Worker.main(@pipeline, input, output, inherited:) }
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
          @batch = 0
          @positions = []
          @records = []
          catch(:worker_gone) do
            Inline.each_record(@pipeline.source, limit: @pipeline.limit, select: @select) do |record, position|
              add(record, position)
            end
            send_batch
          end
          nil
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        ensure
          @handles.each { it.input.close unless it.input.closed? }
        end

        # Adds a record to the batch as Marshal data, taken when it is read, so
        # a source may reuse one object for all its records. Sends the batch
        # when it is full. A record Marshal cannot dump ends the source after
        # the records before it.
        def add(record, position)
          @records << Marshal.dump(record)
          @positions << position
          send_batch if @records.size >= @batch_size
        rescue TypeError => e
          send_batch
          raise Error, "record at position #{position} cannot be sent to a worker: #{e.message}; " \
                       "with --workers, records must be Marshal-able (e.g. parse XML in a step, not in the source)"
        end

        # Sends the batch to the next worker. If that worker is gone, it ended
        # after an error, which the main thread reports when it reaches that
        # batch; the feeding stops.
        def send_batch
          return if @records.empty?

          Frame.write(@handles[@batch % @workers].input, Marshal.dump([@positions, @records]))
          @batch += 1
          @positions = []
          @records = []
        rescue Errno::EPIPE
          throw :worker_gone
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

        # A worker that closed its output without a whole frame has ended. A
        # frame that holds an object of a class this process does not know
        # (Marshal raises ArgumentError) comes from a library the worker
        # loaded after the fork.
        def read(handle)
          Frame.read(handle.output) || ended(handle)
        rescue Frame::Truncated
          ended(handle)
        rescue ArgumentError => e
          raise Error, "worker #{handle.number} sent an object of a class this process does not know (#{e.message}); " \
                       "with --workers, require libraries at job level, not in a step"
        end

        # Raises the signal the worker ended by (SIGINT, SIGTERM), as if this
        # process had got it, else an Error.
        def ended(handle)
          status = reap(handle, deadline)
          raise Interrupt if status.termsig == INTERRUPT
          raise SignalException, TERMINATE if status.termsig == TERMINATE

          message = "worker #{handle.number} (pid #{handle.pid}) ended unexpectedly (#{describe(status)})"
          raise Error, "#{message}#{hint(status)}"
        end

        # Waits for a worker until the deadline, then kills it. Returns its
        # status.
        def reap(handle, limit)
          return handle.status if handle.status

          loop do
            result = Process.waitpid2(handle.pid, Process::WNOHANG)
            return handle.status = result.last if result
            break if now >= limit

            sleep(0.01)
          end
          Process.kill("KILL", handle.pid)
          handle.status = Process.waitpid2(handle.pid).last
        end

        def deadline = now + @stop_timeout

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def describe(status)
          status.signaled? ? "killed by SIG#{Signal.signame(status.termsig)}" : "exit status #{status.exitstatus}"
        end

        # On macOS a forked child crashes with SIGABRT if a gem initialized
        # Objective-C in the parent.
        def hint(status)
          return "" unless RUBY_PLATFORM.include?("darwin") && status.termsig == Signal.list.fetch("ABRT")

          "; on macOS, a gem that uses Objective-C needs OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES (see the Readme)"
        end

        # Ends the feeder and the workers. After a normal end the workers have
        # ended already and are only reaped; otherwise they get SIGTERM and,
        # after the stop timeout, SIGKILL.
        def stop
          @feeder&.kill&.join
          @handles.each(&:close)
          @handles.each { terminate(it) } unless @finished
          limit = deadline
          @handles.each do |handle|
            reap(handle, limit)
            @pipeline.logger.debug { "worker #{handle.number} (pid #{handle.pid}) ended: #{describe(handle.status)}" }
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
