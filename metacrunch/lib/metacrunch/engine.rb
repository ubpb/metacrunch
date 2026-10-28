# frozen_string_literal: true

module Metacrunch
  # Runs a Pipeline: opens the source and the sinks, runs the hooks and has
  # the executor push the records through the steps into the sinks. Applies
  # the failure policy to the run, collects stats and returns a Result.
  class Engine

    # Errors a step can fail with. Everything else (NoMemoryError, signals,
    # SystemExit) ends the process as usual.
    RECOVERABLE = [StandardError, ScriptError, SystemStackError].freeze

    # What Signal.trap reports for SIGTERM when no program trapped it.
    DEFAULT_HANDLERS = ["DEFAULT", "SYSTEM_DEFAULT"].freeze
    STOPPED = "SIGTERM: the source stopped reading; the records read were written"

    # executor: Executor::Inline or Executor::Fork. observer: see Processor.
    # monitor: start(LiveStats) and stop. select: see
    # Executor::Inline.each_record.
    def initialize(pipeline, executor: Executor::Inline.new, observer: nil, monitor: nil, select: nil)
      @pipeline = pipeline
      @executor = executor
      @observer = observer
      @monitor = monitor
      @select = select
    end

    def run
      validate!
      @stats = StatsCollector.new(@pipeline.steps.map(&:name), profile: @pipeline.profile)
      error = stoppable { monitored { execute } }
      @stats.count_written(@pipeline.sink.delivered) if @pipeline.sink
      run_after_hooks(Result.new(status: status_for(error), error:, stats: @stats.snapshot))
    end

    private

    # Lets SIGTERM stop a source that has stop: the run then ends as if the
    # source ended. Sinks that have stop are told too, so one that waits (a
    # queue that is full) gives up instead of holding the run. Only in the
    # main thread and when SIGTERM has its default
    # handler, so a program's own handling stays. A second SIGTERM goes to
    # the default handler, which raises SignalException where interrupts are
    # allowed (Thread.handle_interrupt), as without stop. stop runs in the
    # signal handler. Returns the block's value, the run's error.
    def stoppable
      source = @pipeline.source
      return yield unless source.respond_to?(:stop) && Thread.current.equal?(Thread.main)

      stopped = false
      previous = nil
      handler = proc do
        if stopped
          Signal.trap("TERM", previous)
          Process.kill("TERM", Process.pid)
        else
          stopped = true
          source.stop
          stoppable_sinks.each(&:stop)
        end
      end
      previous = Signal.trap("TERM", handler)
      unless DEFAULT_HANDLERS.include?(previous)
        Signal.trap("TERM", previous)
        return yield
      end

      begin
        error = yield
      ensure
        current = Signal.trap("TERM", previous)
        Signal.trap("TERM", current) unless current.equal?(handler)
      end
      @pipeline.logger.info(STOPPED) if stopped && error.nil?
      error
    end

    def stoppable_sinks
      sinks.map(&:sink).uniq(&:__id__).select { it.respond_to?(:stop) }
    end

    # Tells the monitor about the run. stop runs in any case, also after an
    # abort or a signal.
    def monitored
      return yield unless @monitor

      @monitor.start(LiveStats.new(@stats, @pipeline, workers: @executor.workers))
      begin
        yield
      ensure
        @monitor.stop
      end
    end

    def validate!
      raise ArgumentError, "the pipeline has no source" unless @pipeline.source
      raise ArgumentError, "an observer needs the inline executor" if @observer && @executor.workers > 1

      limit = @pipeline.limit
      return if limit.nil? || (limit.is_a?(Integer) && limit.positive?)

      raise ArgumentError, "limit must be a positive Integer, got #{limit.inspect}"
    end

    def status_for(error)
      return :aborted if error
      return :ok_with_failures if @stats.failed_total.positive?

      :ok
    end

    # Returns the error that aborted the run, or nil. Buffered records are
    # flushed after an abort and on signals (Ctrl-C, SIGTERM); opened
    # components are closed in any case.
    def execute
      opened = []
      error = nil
      begin
        process(opened)
      rescue *RECOVERABLE => e
        error = e
        flush_after_abort
      rescue SignalException
        flush_after_abort
        raise
      ensure
        close_error = Components.close(opened, @pipeline.logger)
      end
      error || close_error
    end

    # The executor opens and closes the step callables itself (in every
    # worker), after the before hooks.
    def process(opened)
      Components.open(components, OpenContext.new(params: @pipeline.params, logger: @pipeline.logger), opened)
      @pipeline.before_hooks.each(&:call)
      outlet = SinkOutlet.new(@pipeline, stats: @stats)
      @executor.run(@pipeline, stats: @stats, outlet:, observer: @observer, select: @select)
      sinks.each(&:flush)
    end

    def sinks
      [@pipeline.sink, @pipeline.rejects, @pipeline.failures].compact
    end

    # Writes what the sinks have buffered, so batch: does not change which
    # records reach a sink when a run stops early. Flush errors are logged;
    # the error that aborted the run stays the run's error.
    def flush_after_abort
      sinks.each do |sink|
        sink.flush
      rescue *RECOVERABLE => e
        @pipeline.logger.error("flushing #{sink.sink.class} after abort failed: #{e.class}: #{e.message}")
      end
    end

    # Source and sinks, in open order. A SinkAdapter stands for its sink, so
    # one object used as sink and rejects opens once.
    def components
      [@pipeline.source, *sinks].uniq do |component|
        component.is_a?(SinkAdapter) ? component.sink.__id__ : component.__id__
      end
    end

    def run_after_hooks(result)
      @pipeline.after_hooks.each do |hook|
        hook.call(result)
      rescue *RECOVERABLE => e
        @pipeline.logger.error("after hook failed: #{e.class}: #{e.message}")
        result = result.with(status: :aborted, error: result.error || e)
      end
      result
    end

  end
end
