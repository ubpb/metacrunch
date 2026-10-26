# frozen_string_literal: true

require "test_helper"

class EngineBatchingTest < Minitest::Test

  include PipelineHelper

  class BatchCollector

    attr_reader :records

    def initialize
      @records = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(records)
      @records.concat(records)
    end

  end

  # Sink without write_batch that is interrupted once while writing record 3.
  class InterruptedOnce

    attr_reader :records

    def initialize
      @records = []
      @interrupted = false
    end

    def write(record)
      if record == 3 && !@interrupted
        @interrupted = true
        raise Interrupt
      end
      @records << record
    end

  end

  class FailingBatch

    def write(_record) = raise("write_batch expected")

    def write_batch(_records) = raise("bulk request failed")

  end

  def test_abort_writes_the_records_that_completed_the_pipeline
    target = BatchCollector.new
    result = run_pipeline do
      source [1, 2, 3, 4, 5]
      map { it == 4 ? raise("boom") : it }
      sink target, batch: 10
    end

    assert_equal [:aborted, [1, 2, 3]], [result.status, target.records]
    assert_equal 3, result.stats.written
  end

  def test_abort_over_max_failures_keeps_the_failed_records_in_a_batched_failures_sink
    failed = BatchCollector.new
    result = run_pipeline do
      source [1, 2, 3, 4]
      map { raise ArgumentError, "bad" }
      failures failed, batch: 100
      on_failure :skip, max_failures: 2
    end

    assert_equal [:aborted, [1, 2, 3]], [result.status, failed.records]
  end

  def test_interrupt_writes_the_records_that_completed_the_pipeline
    target = BatchCollector.new
    pipeline = build_pipeline do
      source [1, 2, 3]
      map { it == 3 ? raise(Interrupt) : it }
      sink target, batch: 10
    end

    assert_raises(Interrupt) { Metacrunch::Engine.new(pipeline).run }
    assert_equal [1, 2], target.records
  end

  def test_interrupt_during_a_per_record_flush_keeps_the_rest
    target = InterruptedOnce.new
    pipeline = build_pipeline do
      source [1, 2, 3, 4, 5]
      sink target, batch: 10
    end

    assert_raises(Interrupt) { engine(pipeline).run }
    assert_equal [1, 2, 3, 4, 5], target.records
  end

  def test_sigterm_flushes_like_interrupt
    target = BatchCollector.new
    pipeline = build_pipeline do
      source [1, 2, 3]
      map { it == 3 ? raise(SignalException, "TERM") : it }
      sink target, batch: 10
    end

    assert_raises(SignalException) { Metacrunch::Engine.new(pipeline).run }
    assert_equal [1, 2], target.records
  end

  def test_records_of_a_failed_batch_are_not_counted_as_written
    result = run_pipeline do
      source [1, 2, 3]
      sink FailingBatch.new, batch: 10
    end

    assert_equal [:aborted, 0], [result.status, result.stats.written]
    assert_match(/bulk request failed/, result.error.message)
  end

  def test_flush_errors_after_an_abort_keep_the_original_error
    result = run_pipeline do
      source [1, 2]
      map { it == 2 ? raise("boom") : it }
      sink FailingBatch.new, batch: 10
    end

    assert_match(/boom/, result.error.message)
  end

end

ForkVariant.define(
  EngineBatchingTest,
  inline_only: [
    :test_interrupt_writes_the_records_that_completed_the_pipeline,
    :test_sigterm_flushes_like_interrupt
  ]
)
