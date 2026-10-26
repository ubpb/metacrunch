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

  # A job or transform without source would read stdin, which is a
  # terminal. target: what was run, as the user named it (a name or path);
  # nil where it is not known. hint says where the records can come from
  # instead.
  class NoInputError < UsageError

    HINT = "pipe them in (< FILE) or use -i PATH"

    attr_reader :target, :hint

    def initialize(target = nil, hint: HINT)
      @target = target
      @hint = hint
      super("#{target || "the job"} reads JSON Lines from stdin, which is a terminal; #{hint}")
    end

    # The same error, naming target.
    def for(target) = self.class.new(target, hint:)

  end

  # A project could not be found or loaded, or a name is unknown or
  # declared more than once. The CLI exits with 2.
  class ProjectError < Error; end

  # A target could not be read: it is missing, a directory, not readable,
  # broken gzip or tar data, a format metacrunch cannot read, or nested too
  # deeply. The message starts with the name of the file or tar member.
  class InputError < Error; end

  # An output could not be opened, written or closed. The message starts
  # with the name of the output.
  class OutputError < Error; end

  # Raised by a sink's write or write_batch when it could not write some
  # records but wrote the others. failed: {index in the batch => error},
  # sorted by index; write reports index 0. The engine applies the failure
  # policy to each of these records under the pseudo-step "sink". Only the
  # job's sink may raise it; from the rejects or failures sink it aborts
  # the run.
  class SinkFailures < Error

    attr_reader :failed

    def initialize(failed)
      unless failed.is_a?(Hash) && !failed.empty? &&
             failed.all? { |index, error| index.is_a?(Integer) && !index.negative? && error.is_a?(Exception) }
        raise ArgumentError,
              "failed must be a non-empty Hash of indices (0 or more) to exceptions, got #{failed.inspect}"
      end

      @failed = failed.sort_by(&:first).to_h.freeze
      first = @failed.each_value.first
      super("#{@failed.size} #{@failed.size == 1 ? "record" : "records"} not written: #{first.class}: #{first.message}")
    end

  end

  # invoke failed: the target is unknown, the arguments are invalid for
  # it, or the job aborted. name: the target as given; result: the Result
  # of an aborted job, else nil. The original error is the cause.
  class InvokeError < Error

    attr_reader :name, :result

    def initialize(message, name:, result: nil)
      @name = name
      @result = result
      super(message)
    end

  end

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
