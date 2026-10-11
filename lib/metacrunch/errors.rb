# frozen_string_literal: true

module Metacrunch

  class Error < StandardError; end

  # Invalid or missing job parameters.
  class ParamError < Error; end

  # A step or sink broke its contract, e.g. a map step returned nil.
  class ContractError < Error; end

  # A job file could not be loaded or does not define the requested job.
  class JobLoadError < Error; end

  # Invalid use of the command line, e.g. options that conflict.
  class UsageError < Error; end

  # A step raised an error for a record. The original error is the cause.
  class StepError < Error

    attr_reader :step, :record_id, :position

    def initialize(step:, record_id:, position:, error:)
      @step = step
      @record_id = record_id
      @position = position
      record = record_id.nil? ? "position #{position}" : "position #{position} (id #{record_id})"
      super("step #{step} failed at #{record}: #{error.class}: #{error.message}")
    end

  end

end
