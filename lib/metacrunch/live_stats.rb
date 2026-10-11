# frozen_string_literal: true

module Metacrunch
  # The counters of a running engine, read when asked for. Monitors such as
  # the progress display read them from another thread; the engine does no
  # extra work for them. Under the GVL reading an Integer is safe, and a
  # slightly stale value is fine.
  class LiveStats

    # workers: the number of processes that run steps.
    def initialize(collector, pipeline, workers: 1)
      @collector = collector
      @pipeline = pipeline
      @workers = workers
    end

    attr_reader :workers

    def read = @collector.read
    def filtered = @collector.filtered_total
    def rejected = @collector.rejected_total
    def failed = @collector.failed_total
    def elapsed = @collector.elapsed

    # Records the sink accepted so far; 0 for jobs without a sink.
    def written
      @pipeline.sink ? @pipeline.sink.delivered : 0
    end

    # The source, for its optional size or progress.
    def source = @pipeline.source

    def limit = @pipeline.limit

  end
end
