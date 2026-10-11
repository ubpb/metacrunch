# frozen_string_literal: true

module Metacrunch

  # Passed to open(context) of sources, steps and sinks.
  OpenContext = Data.define(:params, :logger)

  # Runs a Pipeline: pushes every source record through the chain of steps
  # into the sink, applies the error policy and collects stats.
  class Engine

    # Errors a step can fail with. Everything else (NoMemoryError, signals,
    # SystemExit) ends the process as usual.
    RECOVERABLE = [StandardError, ScriptError, SystemStackError].freeze

    # Returned by map/filter/reject evaluation when the record goes no further.
    DROPPED = Object.new.freeze

    # Wraps errors from later steps and sinks while a flat_map streams its
    # children, so they are not counted as failures of the flat_map step.
    # It inherits from Exception on purpose: the flat_map's Enumerable runs
    # user code around each yield, and a `rescue => e` there must not be
    # able to swallow these errors.
    class DownstreamFailure < Exception # rubocop:disable Lint/InheritException

      attr_reader :original

      def initialize(original)
        @original = original
        super(original.message)
      end

    end

    def initialize(pipeline, executor: Executor::Inline.new, observer: nil)
      @pipeline = pipeline
      @executor = executor
      @observer = observer
    end

    def run
      @stats = StatsCollector.new(@pipeline.steps.map(&:name), profile: @pipeline.profile)
      @on_mark = @stats.method(:mark)
      error = execute
      @stats.count_written(@pipeline.sink.delivered) if @pipeline.sink
      run_after_hooks(Result.new(status: status_for(error), error:, stats: @stats.snapshot))
    end

    private

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
        close_error = close_components(opened)
      end
      error || close_error
    end

    def process(opened)
      open_components(opened)
      @pipeline.before_hooks.each(&:call)
      chain = build_chain
      @executor.run(@pipeline.source) { |record, position| ingest(chain, record, position) }
      sinks.each(&:flush)
    end

    def sinks
      [@pipeline.sink, @pipeline.rejects, @pipeline.errors].compact
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

    # Source, step callables and sinks, in open order. A SinkAdapter stands
    # for its sink, so one object used as sink and rejects opens once.
    def components
      all = [@pipeline.source, *@pipeline.steps.map(&:callable), *sinks]
      all.uniq { |component| component.is_a?(SinkAdapter) ? component.sink.__id__ : component.__id__ }
    end

    def open_components(opened)
      context = OpenContext.new(params: @pipeline.params, logger: @pipeline.logger)
      components.each do |component|
        component.open(context) if component.respond_to?(:open)
        opened << component
      end
    end

    # Closes the opened components in reverse order and returns the first
    # error, after trying to close all of them.
    def close_components(opened)
      first_error = nil
      opened.reverse_each do |component|
        component.close if component.respond_to?(:close)
      rescue *RECOVERABLE => e
        @pipeline.logger.error("closing #{component.class} failed: #{e.class}: #{e.message}")
        first_error ||= e
      end
      first_error
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

    def ingest(chain, record, position)
      @stats.count_read
      return fail_invalid(record, position) if record.is_a?(InvalidRecord)

      id = @pipeline.id_extractor&.call(record)
      chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

    # A record the source could not read fails as the pseudo-step "source".
    # The observer sees it like a step without output.
    def fail_invalid(invalid, position)
      ctx = Context.new(id: nil, position:, logger: @pipeline.logger, on_mark: @on_mark)
      ctx.step = SOURCE_STEP
      @observer&.step_in(SOURCE_STEP, invalid.raw, ctx)
      begin
        @stats.source_failed(invalid.error)
        handle_failure(SOURCE_STEP, invalid.raw, ctx, invalid.error)
      ensure
        @observer&.step_out(SOURCE_STEP, [], ctx)
      end
    end

    def build_chain
      @pipeline.steps.reverse.reduce(method(:deliver)) { |downstream, step| link(step, downstream) }
    end

    # One link of the chain. Only the step itself is covered by the error
    # policy; errors raised further down (later steps, sinks) pass through.
    def link(step, downstream)
      counter = @stats.counter(step.name)
      step.kind == :flat_map ? flat_map_link(step, counter, downstream) : single_link(step, counter, downstream)
    end

    # map, filter and reject: at most one output, no intermediate Array.
    def single_link(step, counter, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        counter.input += 1
        @observer&.step_in(step.name, record, ctx)
        begin
          output = evaluate(step, record, ctx)
        rescue *RECOVERABLE => e
          next fail_observed(step, record, ctx, e)
        end
        @observer&.step_out(step.name, output.equal?(DROPPED) ? [] : [output], ctx)
        if ctx.rejected?
          reject_record(record, ctx)
        elsif output.equal?(DROPPED)
          counter.filtered += 1
        else
          counter.output += 1
          downstream.call(output, ctx)
        end
      end
    end

    # flat_map: streams each child downstream as the step's Enumerable
    # yields it. Children forwarded before an error in the step's own
    # iteration stay forwarded; a reject! during the iteration stops it.
    # The observer's step_out comes after the children went downstream.
    def flat_map_link(step, counter, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        counter.input += 1
        @observer&.step_in(step.name, record, ctx)
        children = @observer ? [] : nil
        begin
          result = timed(step) { step.call(record, ctx) }
          unless ctx.rejected?
            flat_map_contract!(step, result)
            result.each do |child|
              break if ctx.rejected?

              children&.push(child)
              counter.output += 1
              forward_child(downstream, child, ctx)
            end
          end
        rescue DownstreamFailure => e
          raise e.original, cause: e.original.cause
        rescue *RECOVERABLE => e
          next fail_record(step, record, ctx, e)
        ensure
          @observer&.step_out(step.name, children, ctx)
        end
        reject_record(record, ctx) if ctx.rejected?
      end
    end

    def forward_child(downstream, child, ctx)
      downstream.call(child, ctx.copy)
    rescue *RECOVERABLE => e
      raise DownstreamFailure, e
    end

    # Calls a map, filter or reject step. Returns the output record or
    # DROPPED. Raises ContractError if the step breaks its contract.
    def evaluate(step, record, ctx)
      result = timed(step) { step.call(record, ctx) }
      return DROPPED if ctx.rejected?

      case step.kind
      when :map then map_result(step, result)
      when :filter then kept(step, record, ctx, result)
      else kept(step, record, ctx, !result)
      end
    end

    def timed(step)
      return yield unless @pipeline.profile

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        yield
      ensure
        @stats.step_time(step.name, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end

    def kept(step, record, ctx, keep)
      return record if keep

      ctx.reject!(step.reason) if step.reason
      DROPPED
    end

    def map_result(step, result)
      raise ContractError, "map step #{step.name} returned nil" if result.nil?

      result
    end

    def flat_map_contract!(step, result)
      if result.is_a?(Hash)
        raise ContractError, "flat_map step #{step.name} returned a Hash; return [hash] to emit it as one record"
      end
      return if result.respond_to?(:each)

      raise ContractError, "flat_map step #{step.name} must return an Enumerable, got #{result.class}"
    end

    def deliver(record, ctx)
      return unless @pipeline.sink

      @pipeline.sink.write(record, ctx)
    end

    def reject_record(record, ctx)
      rejection = ctx.rejection
      @stats.step_rejected(rejection.step, rejection.reason)
      @pipeline.rejects&.write(record, ctx)
    end

    # Applies the error policy first, so the observer sees ctx.failure
    # under :skip.
    def fail_observed(step, record, ctx, error)
      fail_record(step, record, ctx, error)
    ensure
      @observer&.step_out(step.name, [], ctx)
    end

    def fail_record(step, record, ctx, error)
      @stats.step_failed(step.name, error)
      handle_failure(step.name, record, ctx, error)
    end

    def handle_failure(name, record, ctx, error)
      step_error = StepError.new(step: name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @pipeline.on_error == :abort

      ctx.failure = Failure.new(error:, step: name)
      ctx.logger.error(step_error.message)
      @pipeline.errors&.write(record, ctx)
      check_max_errors(step_error)
    end

    def check_max_errors(step_error)
      max = @pipeline.max_errors
      return unless max && @stats.failed_total > max

      error = Error.new("#{@stats.failed_total} failed records exceed max_errors #{max}")
      raise error, cause: step_error
    end

  end

end
