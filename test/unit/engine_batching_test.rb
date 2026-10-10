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

  def test_abort_over_max_errors_keeps_the_failed_records_in_a_batched_errors_sink
    failed = BatchCollector.new
    result = run_pipeline do
      source [1, 2, 3, 4]
      map { raise ArgumentError, "bad" }
      errors failed, batch: 100
      on_error :skip, max_errors: 2
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
