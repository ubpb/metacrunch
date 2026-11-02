# frozen_string_literal: true

require "etc"

module Metacrunch
  # Executors push the source records through the steps; see Engine.
  module Executor

    # Records per transport batch of Fork, and per segment of Inline
    # (segment_size).
    BATCH_SIZE = 100

    # The records after which both executors run the batch steps on what
    # they hold, so a job gives the same results with and without
    # workers: batch_size for a job without batch steps, else the smallest
    # multiple of its largest batch that is at least batch_size, so that
    # step gets full batches.
    def self.segment_size(pipeline, batch_size)
      largest = pipeline.steps.filter_map(&:batch).max
      largest ? largest * batch_size.ceildiv(largest) : batch_size
    end

    def self.check_batch_size!(batch_size)
      return if batch_size.is_a?(Integer) && batch_size.positive?

      raise ArgumentError, "batch_size must be a positive Integer, got #{batch_size.inspect}"
    end

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
