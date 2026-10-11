# frozen_string_literal: true

require "etc"

module Metacrunch
  # Executors push the source records through the steps; see Engine.
  module Executor

    # Inline for nil or 1, else Fork with that many workers.
    def self.for(workers)
      unless workers.nil? || (workers.is_a?(Integer) && workers.positive?)
        raise ArgumentError, "workers must be a positive Integer, got #{workers.inspect}"
      end

      workers.nil? || workers == 1 ? Inline.new : Fork.new(workers:)
    end

    # The workers for "auto": one per core but one, which the parent needs
    # for the source, the sinks and Marshal.
    def self.auto_workers = [Etc.nprocessors - 1, 1].max

  end
end
