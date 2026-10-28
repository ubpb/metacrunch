# frozen_string_literal: true

module Metacrunch

  # Outcome of a run. status is :ok, :ok_with_failures or :aborted; error
  # is the error that aborted the run. stopped: SIGTERM stopped the source,
  # and the run ended as if the source had ended.
  Result = Data.define(:status, :error, :stats, :stopped) do
    def initialize(stopped: false, **) = super

    def ok? = status == :ok

    def summary
      text = "#{status}: #{stats.summary}"
      error ? "#{text}; #{error.class}: #{error.message}" : text
    end
  end

  # Outcome of invoking a command. status is :ok, or :ok_with_failures if a
  # job run during its body (also through nested commands) ended with
  # failures, or aborted and the body went on; value is what the body
  # returned. error is nil: an exception that leaves the body passes
  # unchanged. Shares status, ok? and error with Result.
  CommandResult = Data.define(:status, :error, :value) do
    def ok? = status == :ok
  end

end
