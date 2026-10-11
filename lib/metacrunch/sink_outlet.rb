# frozen_string_literal: true

module Metacrunch
  # Writes the records that leave the chain of steps to the pipeline's
  # sinks: delivered ones to the sink, rejected ones to rejects and failed
  # ones to errors. Enforces max_errors, so a run stops at the same record
  # whether its steps run inline or in workers.
  class SinkOutlet

    def initialize(pipeline)
      @sink = pipeline.sink
      @rejects = pipeline.rejects
      @errors = pipeline.errors
      @max_errors = pipeline.max_errors
      @failed = 0
    end

    def deliver(record, ctx)
      @sink&.write(record, ctx)
    end

    def reject(record, ctx)
      @rejects&.write(record, ctx)
    end

    # ctx.failure is set. Raises Error once the failed records exceed
    # max_errors, with the StepError of this record as the cause.
    def fail(record, ctx)
      @errors&.write(record, ctx)
      @failed += 1
      return unless @max_errors && @failed > @max_errors

      failure = ctx.failure
      step_error = StepError.new(step: failure.step, record_id: ctx.id, position: ctx.position, error: failure.error)
      raise Error, "#{@failed} failed records exceed max_errors #{@max_errors}", cause: step_error
    end

  end
end
