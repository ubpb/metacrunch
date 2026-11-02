# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

# Batch steps inline with segments of three records; ForkVariant runs the same tests with two workers and
# transport batches of three, which must give the same results.
class EngineBatchStepsTest < Minitest::Test

  include PipelineHelper

  FLUSH = Metacrunch::FLUSH

  def executor = Metacrunch::Executor::Inline.new(batch_size: 3)

  # A batch function that pairs each record with the size of its batch.
  SIZES = ->(records) { records.map { [it, records.size] } }

  # Segments of three records (the multiple of the largest batch, 3): the step with batch 2 is cut at their ends.
  def test_batch_steps_see_the_same_batches_inline_and_in_workers
    target = CollectingSink.new
    run_pipeline do
      source (1..7).to_a
      map SIZES, batch: 2
      map(batch: 3) { |records| records }
      sink target
    end

    assert_equal [[1, 2], [2, 2], [3, 1], [4, 2], [5, 2], [6, 1], [7, 1]], target.records
  end

  def test_the_sink_gets_source_order
    target = CollectingSink.new
    run_pipeline do
      source (1..9).to_a
      filter { it % 3 != 0 }
      map(batch: 2) { |records| records.map { it * 10 } }
      sink target
    end

    assert_equal [10, 20, 40, 50, 70, 80], target.records
  end

  def test_rejects_and_failures_get_processing_order
    rejected = CollectingSink.new
    failed = CollectingSink.new
    run_pipeline do
      source (1..3).to_a
      reject("Early") { it == 2 }
      map(batch: 3) { |records| records.map { it == 1 ? RuntimeError.new("late") : it } }
      reject("Late") { it == 3 }
      rejects rejected
      failures failed
      on_failure :skip
    end

    assert_equal [2, 3], rejected.records
    assert_equal [1], failed.records
  end

  def test_max_failures_stops_at_the_same_record_inline_and_in_workers
    failed = CollectingSink.new
    result = run_pipeline do
      source (1..6).to_a
      map { it == 2 ? raise("early") : it }
      map(batch: 3) { |records| records.map { it.odd? ? RuntimeError.new("late") : it } }
      failures failed
      on_failure :skip, max_failures: 2
    end

    assert_equal :aborted, result.status
    assert_equal [2, 1, 3], failed.records
    assert_equal 3, result.error.cause.position
  end

  def test_flush_from_the_source_runs_the_batch_steps
    target = CollectingSink.new
    run_pipeline do
      source [1, 2, FLUSH, 3]
      map SIZES, batch: 5
      sink target
    end

    assert_equal [[1, 2], [2, 2], [3, 1]], target.records
  end

  def test_two_batch_steps_and_a_flush_in_a_segment
    target = CollectingSink.new
    run_pipeline do
      source [1, 2, FLUSH, 3, 4, 5, 6, 7]
      map(batch: 2) { |records| records.map { it * 10 } }
      map(batch: 3) { |records| records.map { it + 1 } }
      sink target
    end

    assert_equal [11, 21, 31, 41, 51, 61, 71], target.records
  end

  def test_flat_map_children_before_a_batch_step
    target = CollectingSink.new
    run_pipeline do
      source [1, 2, 3]
      flat_map { |record| [record, record * 10, record * 100] }
      map SIZES, batch: 2
      sink target
    end

    assert_equal [1, 10, 100, 2, 20, 200, 3, 30, 300], target.records.map(&:first)
    assert_equal [1, 1, 1, 2, 2, 2, 3, 3, 3], target.contexts.map(&:position)
  end

  def test_limit_flushes_the_batch_steps
    target = CollectingSink.new
    pipeline = build_pipeline do
      source (1..10).to_a
      map(batch: 3) { |records| records }
      sink target
    end
    engine(pipeline.with(limit: 4)).run

    assert_equal [1, 2, 3, 4], target.records
  end

  def test_an_abort_drops_buffered_records
    target = CollectingSink.new
    result = run_pipeline do
      source (1..5).to_a
      map { it == 3 ? raise("x") : it }
      map(batch: 3) { |records| records }
      sink target
    end

    assert_equal :aborted, result.status
    assert_empty target.records
    assert_equal 0, result.stats.steps.fetch("map#2").input
  end

  def test_transform_batch_steps_work_through_use
    batched = Metacrunch.transform("batched") { map(batch: 2) { |records| records.map { it + 1 } } }
    job = Metacrunch.job { use batched }
    workers = executor.workers > 1 ? executor.workers : nil

    assert_equal [2, 3, 4], Metacrunch::Testing.run(job, source: [1, 2, 3], workers:).records
  end

end

ForkVariant.define(EngineBatchStepsTest, inline_only: [:test_an_abort_drops_buffered_records])
