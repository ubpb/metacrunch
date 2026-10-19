# frozen_string_literal: true

module Metacrunch
  # Writes the records that leave the chain of steps to the pipeline's
  # sinks: delivered ones to the sink, rejected ones to rejects and failed
  # ones to failures. Enforces max_failures, so a run stops at the same record
  # whether its steps run inline or in workers.
  class SinkOutlet

    def initialize(pipeline)
      @sink = pipeline.sink
      @rejects = pipeline.rejects
      @failures = pipeline.failures
      @max_failures = pipeline.max_failures
      @failed = 0
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

  end
end
