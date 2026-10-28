# frozen_string_literal: true

require "test_helper"

class EngineFlushTest < Minitest::Test

  include PipelineHelper

  # A batching sink; Mutex, since with workers the source reads it from the feeder thread.
  class BatchCollector

    def initialize
      @lock = Mutex.new
      @batches = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(records)
      @lock.synchronize { @batches << records.dup }
    end

    def batches = @lock.synchronize { @batches.dup }

    def records = batches.flatten

  end

  # Yields the values; for [:wait, n], waits until the collector holds n records and notes what it held.
  class Flushing

    attr_reader :seen

    def initialize(collector, *values)
      @collector = collector
      @values = values
      @seen = []
    end

    def each
      @values.each do |value|
        next @seen << wait_for(value.last) if value.is_a?(Array)

        yield value
      end
    end

    private

    def wait_for(count)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      sleep(0.01) while @collector.records.size < count && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      @collector.records
    end

  end

  FLUSH = Metacrunch::FLUSH

  def test_flush_is_a_frozen_constant_that_names_itself
    assert_predicate FLUSH, :frozen?
    assert_equal "Metacrunch::FLUSH", FLUSH.inspect
  end

  def test_a_flush_writes_the_batched_records_before_the_source_goes_on
    target = BatchCollector.new
    source = Flushing.new(target, 1, 2, FLUSH, [:wait, 2], 3)
    result = run_pipeline do
      source source
      sink target, batch: 10
    end

    assert_equal :ok, result.status
    assert_equal [[1, 2]], source.seen
    assert_equal [1, 2, 3], target.records
  end

  def test_a_flush_is_no_record
    positions = []
    result = run_pipeline do
      source [1, FLUSH, 2, FLUSH, 3]
      map do |record, ctx|
        positions << ctx.position
        record
      end
      sink BatchCollector.new, batch: 10
    end

    assert_equal 3, result.stats.read
    assert_equal [1, 2, 3], positions unless executor.workers > 1
  end

  def test_a_flush_counts_toward_no_limit
    target = BatchCollector.new
    pipeline = build_pipeline do
      source [FLUSH, 1, FLUSH, 2, 3]
      sink target, batch: 10
    end
    engine(pipeline.with(limit: 2)).run

    assert_equal [1, 2], target.records
  end

  def test_a_flush_with_nothing_buffered_writes_nothing
    target = BatchCollector.new
    run_pipeline do
      source [FLUSH, FLUSH, 1]
      sink target, batch: 10
    end

    assert_equal [[1]], target.batches
  end

  def test_a_flush_writes_the_rejects_and_failures_sinks_too
    rejected = BatchCollector.new
    failed = BatchCollector.new
    source = Flushing.new(failed, 1, 2, FLUSH, [:wait, 1], 3)
    run_pipeline do
      source source
      reject("Odd", &:odd?)
      map { it == 2 ? raise("two") : it }
      rejects rejected, batch: 10
      failures failed, batch: 10
      on_failure :skip
    end

    assert_equal [[2]], source.seen
    assert_equal [[1], [3]], rejected.batches
  end

  # A sink that buffers on its own, as a file does, and notes when it was told to flush.
  class Buffering

    attr_reader :log

    def initialize
      @log = []
    end

    def write(record) = @log << record

    def flush = @log << :flush

  end

  def test_a_flush_lets_a_sink_write_what_it_buffers_itself
    target = Buffering.new
    run_pipeline do
      source [1, FLUSH, 2]
      sink target
    end

    assert_equal [1, :flush, 2], target.log
  end

  def test_flushes_between_partial_worker_batches_keep_the_order
    target = BatchCollector.new
    run_pipeline do
      source [1, 2, FLUSH, 3, 4, FLUSH, 5]
      sink target, batch: 10
    end

    assert_equal [[1, 2], [3, 4], [5]], target.batches
  end

end

ForkVariant.define(EngineFlushTest)
