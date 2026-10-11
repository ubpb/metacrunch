# frozen_string_literal: true

module Metacrunch

  class Error < StandardError; end

  # Invalid or missing job parameters.
  class ParamError < Error; end

  # Credentials could not be read: no key, a wrong key, a damaged file,
  # invalid YAML or an invalid environment name. A ParamError, because it
  # happens while parameters are bound; the CLI exits with 2.
  class CredentialsError < ParamError; end

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

  # Stands in for an exception that a worker process cannot send to the
  # parent because Marshal cannot dump it (e.g. it holds an IO). Keeps the
  # original class name, message and backtrace.
  class WorkerError < Error

    attr_reader :original_class, :original_message

    def initialize(original_class, original_message)
      @original_class = original_class
      @original_message = original_message
      super("#{original_class}: #{original_message}")
    end

  end

end
