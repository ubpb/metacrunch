# frozen_string_literal: true

require "test_helper"

class ResultTest < Minitest::Test

  def test_summary_names_status_and_error
    result = Metacrunch::Result.new(status: :aborted, error: RuntimeError.new("boom"), stats:)

    assert_equal "aborted: read 1, written 0 in 1.00s (1 records/s); RuntimeError: boom", result.summary
    refute_predicate result, :ok?
  end

  def test_summary_without_error
    result = Metacrunch::Result.new(status: :ok, error: nil, stats:)

    assert_equal "ok: read 1, written 0 in 1.00s (1 records/s)", result.summary
    assert_predicate result, :ok?
  end

  private

  def stats
    Metacrunch::Stats.new(
      read: 1, written: 0, filtered: 0, rejected: {}, marked: {}, failed: {}, steps: {}, duration: 1.0
    )
  end

end
