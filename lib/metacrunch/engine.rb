# frozen_string_literal: true

module Metacrunch
  # Runs a Pipeline: pushes every source record through the chain of steps
  # into the sink and collects stats.
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
      Result.new(status: error ? :aborted : :ok, error:, stats: @stats.snapshot)
    end

    private

    # Returns the error that aborted the run, or nil.
    def execute
      chain = build_chain
      @executor.run(@pipeline.source) { |record, position| ingest(chain, record, position) }
      sinks.each(&:flush)
      nil
    rescue StandardError => e
      e
    end

    def sinks
      [@pipeline.sink, @pipeline.rejects, @pipeline.errors].compact
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
    # the step itself is covered by the error handling; errors raised
    # further down (later steps, sinks) pass through.
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
      result = step.call(record, ctx)
      return [] if ctx.rejected?

      case step.kind
      when :map then [map_result(step, result)]
      when :filter then kept(step, record, ctx, result)
      when :reject then kept(step, record, ctx, !result)
      else flat_map_result(step, result)
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
      @stats.count_written
    end

    def reject_record(record, ctx)
      rejection = ctx.rejection
      @stats.step_rejected(rejection.step, rejection.reason)
      @pipeline.rejects&.write(record, ctx)
    end

    def fail_record(step, _record, ctx, error)
      @stats.step_failed(step.name, error)
      step_error = StepError.new(step: step.name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error
    end

  end
end
