# frozen_string_literal: true

module Metacrunch

  STEP_KINDS = [:map, :filter, :reject, :flat_map].freeze

  # One step of a pipeline. reason is set for filter/reject steps that
  # reject (instead of silently filter) the records they drop.
  Step = Data.define(:kind, :callable, :name, :reason, :pass_context) do
    def self.build(kind, callable, name:, reason: nil)
      raise ArgumentError, "unknown step kind #{kind.inspect}" unless STEP_KINDS.include?(kind)

      Callable.ensure_callable!(callable, "#{kind} step #{name}")
      new(kind:, callable:, name:, reason:, pass_context: Callable.accepts_second_argument?(callable))
    end

    def call(record, ctx)
      pass_context ? callable.call(record, ctx) : callable.call(record)
    end
  end

end
