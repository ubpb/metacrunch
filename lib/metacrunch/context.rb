# frozen_string_literal: true

module Metacrunch

  Rejection = Data.define(:reason, :value, :step)
  Mark = Data.define(:reason, :value, :step)
  Failure = Data.define(:error, :step)

  # Per-record context. The engine creates one for every record the source
  # emits and passes it to steps and sinks that accept a second argument.
  class Context

    # What a sink can read of a context, as plain values. It crosses the
    # boundary between a worker and the parent (Executor::Fork).
    State = Data.define(:id, :position, :step, :marks, :store, :rejection, :failure)

    # Raised by reject! to end the step; the engine rescues it around every
    # step. It inherits from Exception on purpose, so a `rescue => e` in a
    # step cannot swallow the rejection.
    class Rejected < Exception; end # rubocop:disable Lint/InheritException

    attr_reader :id, :position, :marks, :store, :rejection
    attr_accessor :step, :failure

    # Reasons are counted and reported as Strings. Symbols are converted;
    # nil and empty reasons break the contract.
    def self.reason(reason)
      text = reason.is_a?(Symbol) ? reason.to_s : reason
      return text if text.is_a?(String) && !text.empty?

      raise ContractError, "a reason must be a non-empty String or Symbol, got #{reason.inspect}"
    end

    # A context from a State, with this process's logger. It counts no
    # marks: they were counted where they were made.
    def self.from_state(state, logger:)
      new(id: state.id, position: state.position, logger:, marks: state.marks, store: state.store,
          rejection: state.rejection).tap do |ctx|
        ctx.step = state.step
        ctx.failure = state.failure
      end
    end

    # on_mark is called with the reason of every mark, so marks are counted
    # when they happen (once, even if a flat_map copies the context later).
    def initialize(id:, position:, logger:, on_mark: nil, marks: [], store: {}, rejection: nil)
      @id = id
      @position = position
      @base_logger = logger
      @on_mark = on_mark
      @marks = marks
      @store = store
      @rejection = rejection
      @failure = nil
      @step = nil
      @sealed = false
    end

    # Stops processing of this record: records the rejection and ends the
    # current step by raising Rejected. The engine sends the record to the
    # rejects sink.
    def reject!(reason, value: nil)
      record_rejection(reason, value:)
      raise Rejected, @rejection.reason
    end

    # Records a rejection without ending the step. The engine uses it for
    # filter and reject steps with a reason; steps call reject!.
    def record_rejection(reason, value: nil)
      ensure_writable!
      @rejection = Rejection.new(reason: Context.reason(reason), value:, step:)
      nil
    end

    def rejected?
      !@rejection.nil?
    end

    # Records a non-fatal note. The record continues through the pipeline.
    def mark(reason, value: nil)
      ensure_writable!
      reason = Context.reason(reason)
      @marks << Mark.new(reason:, value:, step:)
      @on_mark&.call(reason)
      nil
    end

    def logger
      @logger ||= RecordLogger.new(@base_logger, id.nil? ? "##{position}" : id)
    end

    def to_state = State.new(id:, position:, step:, marks:, store:, rejection:, failure:)

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
