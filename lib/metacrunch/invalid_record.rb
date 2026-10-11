# frozen_string_literal: true

module Metacrunch

  # Yielded by a source for a record it could not read, e.g. a line that is
  # not valid JSON. raw is what the source read, error why it failed. The
  # engine counts it as a failure of the pseudo-step "source" under the
  # job's error policy.
  InvalidRecord = Data.define(:raw, :error)

end
