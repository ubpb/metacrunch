# frozen_string_literal: true

require "test_helper"

class ExecutorTest < Minitest::Test

  include Override
  include PipelineHelper

  def test_segment_size_without_batch_steps_is_the_batch_size
    assert_equal 100, Metacrunch::Executor.segment_size(build_pipeline { map { it } }, 100)
  end

  def test_segment_size_is_the_smallest_multiple_of_the_largest_batch_at_least_the_batch_size
    pipeline = build_pipeline do
      map(batch: 30) { it }
      map(batch: 7) { it }
    end
    sizes = [[pipeline, 100], [build_pipeline { map(batch: 500) { it } }, 100],
             [build_pipeline { map(batch: 5) { it } }, 3], [build_pipeline { map(batch: 100) { it } }, 100]]

    assert_equal([120, 500, 5, 100], sizes.map { |p, base| Metacrunch::Executor.segment_size(p, base) })
  end

  def test_the_batch_size_is_shared_by_both_executors
    sizes = [Metacrunch::Executor::BATCH_SIZE, Metacrunch::Executor::Fork::BATCH_SIZE,
             Metacrunch::Executor::Inline.new.batch_size]

    assert_equal [100, 100, 100], sizes
    assert_equal 3, Metacrunch::Executor::Inline.new(batch_size: 3).batch_size
  end

  def test_inline_refuses_other_batch_sizes
    error = assert_raises(ArgumentError) { Metacrunch::Executor::Inline.new(batch_size: 0) }

    assert_equal "batch_size must be a positive Integer, got 0", error.message
  end

  def test_picks_inline_for_one_worker_and_fork_for_more
    assert_instance_of Metacrunch::Executor::Inline, Metacrunch::Executor.for(nil)
    assert_instance_of Metacrunch::Executor::Inline, Metacrunch::Executor.for(1)
    assert_equal 3, Metacrunch::Executor.for(3).workers
  end

  def test_refuses_other_numbers
    error = assert_raises(ArgumentError) { Metacrunch::Executor.for(0) }

    assert_equal "workers must be a positive Integer, got 0", error.message
  end

  def test_auto_leaves_a_core_for_the_parent
    counts = [1, 8].map do |cores|
      override(Etc, :nprocessors, -> { cores }) { Metacrunch::Executor.auto_workers }
    end

    assert_equal [1, 7], counts
  end

end
