# frozen_string_literal: true

module Metacrunch

  # Immutable description of one run, built from a job's recipe by Builder.
  # sink, rejects and failures are SinkAdapter instances or nil. source is
  # nil for jobs that read the CLI's default input. on_failure and
  # max_failures: the failure policy. limit stops the run after that many
  # records (nil: no limit).
  Pipeline = Data.define(
    :source, :id_extractor, :steps, :sink, :rejects, :failures,
    :on_failure, :max_failures, :profile, :before_hooks, :after_hooks, :params, :logger, :limit
  )

end
