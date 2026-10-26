# frozen_string_literal: true

# Hooks that must not run in a trace.
Metacrunch.job do
  source [1]
  before { raise "the before hook must not run" }
  after { raise "the after hook must not run" }
end
