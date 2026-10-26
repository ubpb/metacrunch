# frozen_string_literal: true

require "test_helper"

class ExecutorTest < Minitest::Test

  include Override

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
