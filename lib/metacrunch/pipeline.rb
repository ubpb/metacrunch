# frozen_string_literal: true

module Metacrunch

  # Immutable description of one run, built from a job's recipe by Builder.
  # sink, rejects and errors are SinkAdapter instances or nil.
  Pipeline = Data.define(
    :source, :id_extractor, :steps, :sink, :rejects, :errors,
    :on_error, :max_errors, :profile, :before_hooks, :after_hooks, :params, :logger
  )

end
