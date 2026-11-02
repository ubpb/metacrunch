# frozen_string_literal: true

module Metacrunch

  STEP_KINDS = [:map, :filter, :reject, :flat_map].freeze

  # Failures of the source (InvalidRecord) are reported under this name; no
  # step may use it.
  SOURCE_STEP = "source"

  # Records the sink reports as not written (SinkFailures) fail under this
  # name; no step may use it.
  SINK_STEP = "sink"

  # One step of a pipeline. reason is set for filter/reject steps that
  # reject (instead of silently filter) the records they drop. batch: nil,
  # or the most records the step gets at once (call_batch); pass_context
  # then tells whether its batch function takes the contexts.
  Step = Data.define(:kind, :callable, :name, :reason, :pass_context, :batch) do
    def self.build(kind, callable, name:, reason: nil, batch: nil)
      raise ArgumentError, "unknown step kind #{kind.inspect}" unless STEP_KINDS.include?(kind)
      return per_record(kind, callable, name, reason) if batch.nil?

      unless batch.is_a?(Integer) && batch.positive?
        raise ArgumentError, "#{kind} step #{name}: batch must be a positive Integer, got #{batch.inspect}"
      end

      function = batch_function(callable)
      raise ArgumentError, "#{kind} step #{name}: batch: needs an object with call_batch, or a block" unless function

      new(kind:, callable:, name:, reason:, pass_context: Callable.accepts_second_argument?(function), batch:)
    end

    def self.per_record(kind, callable, name, reason)
      Callable.ensure_callable!(callable, "#{kind} step #{name}")
      new(kind:, callable:, name:, reason:, pass_context: Callable.accepts_second_argument?(callable), batch: nil)
    end

    # A Proc or Method is the batch function itself; other objects bring
    # call_batch. nil if there is none.
    def self.batch_function(callable)
      return callable if callable.is_a?(Proc) || callable.is_a?(Method)

      callable.method(:call_batch) if callable.respond_to?(:call_batch)
    end

    private_class_method :per_record, :batch_function

    def call(record, ctx)
      pass_context ? callable.call(record, ctx) : callable.call(record)
    end

    # Calls the batch function with the records, and the contexts if it
    # takes them.
    def call_batch(records, ctxs)
      function = callable.is_a?(Proc) || callable.is_a?(Method) ? callable : callable.method(:call_batch)
      pass_context ? function.call(records, ctxs) : function.call(records)
    end
  end

end
