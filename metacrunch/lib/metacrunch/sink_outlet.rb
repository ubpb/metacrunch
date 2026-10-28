# frozen_string_literal: true

module Metacrunch
  # Writes the records that leave the chain of steps to the pipeline's
  # sinks: delivered ones to the sink, rejected ones to rejects and failed
  # ones to failures. Enforces max_failures, so a run stops at the same record
  # whether its steps run inline or in workers. Applies the failure policy to
  # the records the sink reports as not written (SinkFailures).
  class SinkOutlet

    def initialize(pipeline, stats:)
      @sink = pipeline.sink
      @rejects = pipeline.rejects
      @failures = pipeline.failures
      @on_failure = pipeline.on_failure
      @max_failures = pipeline.max_failures
      @stats = stats
      @failed = 0
      @sink&.failure_handler = method(:sink_failed)
    end

    # Writes what the sinks buffer (a FLUSH of the source): the records each
    # adapter holds for batch:, then the sink's own buffer through its
    # optional flush, once per sink object, also when it serves two roles.
    def flush
      adapters = [@sink, @rejects, @failures].compact
      adapters.each(&:flush)
      adapters.map(&:sink).uniq(&:__id__).each { it.flush if it.respond_to?(:flush) }
    end

    def deliver(record, ctx)
      @sink&.write(record, ctx)
    end

    def reject(record, ctx)
      @rejects&.write(record, ctx)
    end

    # ctx.failure is set. Raises Error once the failed records exceed
    # max_failures, with the StepError of this record as the cause.
    def fail(record, ctx)
      @failures&.write(record, ctx)
      @failed += 1
      return unless @max_failures && @failed > @max_failures

      failure = ctx.failure
      step_error = StepError.new(step: failure.step, record_id: ctx.id, position: ctx.position, error: failure.error)
      raise Error, "#{@failed} failed records exceed max_failures #{@max_failures}", cause: step_error
    end

    private

    # A record the sink did not write fails as the pseudo-step "sink", under
    # the same policy as a failing step (Processor#handle_failure).
    def sink_failed(record, ctx, error)
      @stats.record_failed(error)
      step_error = StepError.new(step: SINK_STEP, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @on_failure == :abort

      ctx.failure = Failure.new(error:, step: SINK_STEP)
      ctx.logger.error(step_error.message)
      fail(record, ctx)
    end

  end
end
