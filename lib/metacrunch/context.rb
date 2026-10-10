# frozen_string_literal: true

module Metacrunch

  Rejection = Data.define(:reason, :value, :step)
  Mark = Data.define(:reason, :value, :step)
  Failure = Data.define(:error, :step)

  # Per-record context. The engine creates one for every record the source
  # emits and passes it to steps and sinks that accept a second argument.
  class Context

    attr_reader :id, :position, :marks, :store, :rejection
    attr_accessor :step, :failure

    # on_mark is called with the reason of every mark, so marks are counted
    # when they happen (once, even if a flat_map copies the context later).
    def initialize(id:, position:, logger:, on_mark: nil, marks: [], store: {})
      @id = id
      @position = position
      @base_logger = logger
      @on_mark = on_mark
      @marks = marks
      @store = store
      @rejection = nil
      @failure = nil
      @step = nil
      @sealed = false
    end

    # Stops processing of this record. The engine sends it to the rejects
    # sink and ignores the return value of the current step.
    def reject!(reason, value: nil)
      ensure_writable!
      @rejection = Rejection.new(reason:, value:, step:)
      nil
    end

    def rejected?
      !@rejection.nil?
    end

    # Records a non-fatal note. The record continues through the pipeline.
    def mark(reason, value: nil)
      ensure_writable!
      @marks << Mark.new(reason:, value:, step:)
      @on_mark&.call(reason)
      nil
    end

    def logger
      @logger ||= RecordLogger.new(@base_logger, id.nil? ? "##{position}" : id)
    end

    # A copy for one child of a flat_map step: same id and position, own
    # marks and store.
    def copy
      child = self.class.new(
        id:, position:, logger: @base_logger, on_mark: @on_mark, marks: marks.dup, store: store.dup
      )
      child.step = step
      child
    end

    # Sinks get sealed contexts: they may read them, but not reject or mark.
    def seal!
      @sealed = true
      self
    end

    private

    def ensure_writable!
      return unless @sealed

      raise ContractError, "the context is read-only in sinks; reject or mark records in a step"
    end

  end

end
