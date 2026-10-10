# frozen_string_literal: true

module Metacrunch

  # Outcome of a run. status is :ok, :ok_with_failures or :aborted; error
  # is the error that aborted the run.
  Result = Data.define(:status, :error, :stats) do
    def ok? = status == :ok

    def summary
      text = "#{status}: #{stats.summary}"
      error ? "#{text}; #{error.class}: #{error.message}" : text
    end
  end

end
