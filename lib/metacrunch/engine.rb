# frozen_string_literal: true

module Metacrunch

  # Passed to open(context) of sources, steps and sinks.
  OpenContext = Data.define(:params, :logger)

  # Runs a Pipeline: pushes every source record through the chain of steps
  # into the sink, applies the error policy and collects stats.
  class Engine

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

    # Returns the error that aborted the run, or nil. Opened components are
    # closed in any case, also while an Interrupt propagates.
    def execute
      opened = []
      error = nil
      begin
        process(opened)
      rescue StandardError => e
        error = e
        flush_after_abort
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
    # records reach a sink when a run aborts. Flush errors are logged; the
    # error that aborted the run stays the run's error.
    def flush_after_abort
      sinks.each do |sink|
        sink.flush
      rescue StandardError => e
        @pipeline.logger.error("flushing #{sink.sink.class} after abort failed: #{e.class}: #{e.message}")
      end
    end

    # Source, step callables and sinks, in open order.
    def components
      [@pipeline.source, *@pipeline.steps.map(&:callable), *sinks].uniq(&:__id__)
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
      rescue StandardError => e
        @pipeline.logger.error("closing #{component.class} failed: #{e.class}: #{e.message}")
        first_error ||= e
      end
      first_error
    end

    def run_after_hooks(result)
      @pipeline.after_hooks.each do |hook|
        hook.call(result)
      rescue StandardError => e
        @pipeline.logger.error("after hook failed: #{e.class}: #{e.message}")
        result = result.with(status: :aborted, error: result.error || e)
      end
      result
    end

    def ingest(chain, record, position)
      @stats.count_read
      id = @pipeline.id_extractor&.call(record)
      chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

    def build_chain
      @pipeline.steps.reverse.reduce(method(:deliver)) { |downstream, step| link(step, downstream) }
    end

    # One link of the chain: runs the step and passes its outputs on. Only
    # the step itself is covered by the error policy; errors raised further
    # down (later steps, sinks) pass through.
    def link(step, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        @stats.step_in(step.name)
        @observer&.step_in(step.name, record, ctx)
        begin
          outputs = evaluate(step, record, ctx)
        rescue StandardError => e
          @observer&.step_out(step.name, [], ctx)
          next fail_record(step, record, ctx, e)
        end
        @observer&.step_out(step.name, outputs, ctx)
        forward(step, record, ctx, outputs, downstream)
      end
    end

    # Calls the step and returns its outputs as an Array. Raises
    # ContractError if the step breaks its contract.
    def evaluate(step, record, ctx)
      result = timed(step) { step.call(record, ctx) }
      return [] if ctx.rejected?

      case step.kind
      when :map then [map_result(step, result)]
      when :filter then kept(step, record, ctx, result)
      when :reject then kept(step, record, ctx, !result)
      else flat_map_result(step, result)
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
      return [record] if keep

      ctx.reject!(step.reason) if step.reason
      []
    end

    def map_result(step, result)
      raise ContractError, "map step #{step.name} returned nil" if result.nil?

      result
    end

    def flat_map_result(step, result)
      if result.is_a?(Hash)
        raise ContractError, "flat_map step #{step.name} returned a Hash; return [hash] to emit it as one record"
      end
      unless result.respond_to?(:each)
        raise ContractError, "flat_map step #{step.name} must return an Enumerable, got #{result.class}"
      end

      # The contract only requires #each, so #map may not exist.
      outputs = []
      result.each { |output| outputs << output } # rubocop:disable Style/MapIntoArray
      outputs
    end

    def forward(step, record, ctx, outputs, downstream)
      if ctx.rejected?
        reject_record(record, ctx)
      elsif step.kind == :flat_map
        @stats.step_out(step.name, outputs.size)
        outputs.each { |child| downstream.call(child, ctx.copy) }
      elsif outputs.empty?
        @stats.step_filtered(step.name)
      else
        @stats.step_out(step.name)
        downstream.call(outputs.first, ctx)
      end
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

    def fail_record(step, record, ctx, error)
      @stats.step_failed(step.name, error)
      step_error = StepError.new(step: step.name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @pipeline.on_error == :abort

      ctx.failure = Failure.new(error:, step: step.name)
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
