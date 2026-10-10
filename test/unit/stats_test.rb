# frozen_string_literal: true

require "test_helper"

class StatsTest < Minitest::Test

  def test_merge_adds_counts_and_keeps_the_longer_duration
    a = stats(read: 2, rejected: {"Patent" => 1}, steps: {"map#1" => step(input: 2, output: 2)}, duration: 1.0)
    b = stats(read: 3, rejected: {"Patent" => 2, "Private" => 1}, steps: {"map#1" => step(input: 3, output: 1)},
              duration: 2.5)
    merged = a.merge(b)

    assert_equal [5, {"Patent" => 3, "Private" => 1}, 2.5], [merged.read, merged.rejected, merged.duration]
    assert_equal step(input: 5, output: 3), merged.steps["map#1"]
  end

  def test_summary_lists_reasons_and_omits_zero_counts
    text = stats(read: 10, written: 8, rejected: {"Patent" => 2}, duration: 2.0).summary

    assert_equal "read 10, written 8, rejected 2 (Patent: 2) in 2.00s (5 records/s)", text
  end

  def test_summary_shows_filtered_marked_and_failed_counts
    text = Metacrunch::Stats.new(
      read: 4, written: 1, filtered: 1, rejected: {}, marked: {"No title" => 2}, failed: {"KeyError" => 1},
      steps: {}, duration: 0.0
    ).summary
    expected = "read 4, written 1, filtered 1, marked 2 (No title: 2), failed 1 (KeyError: 1) " \
               "in 0.00s (0 records/s)"

    assert_equal expected, text
  end

  def test_step_merge_adds_times_only_when_profiled
    profiled = step(input: 1, output: 1).with(time: 0.5)
    plain = step(input: 1, output: 1)

    assert_in_delta 0.75, profiled.merge(profiled.with(time: 0.25)).time
    assert_nil plain.merge(plain).time
  end

  def test_to_h_includes_rate_and_step_hashes
    hash = stats(read: 4, steps: {"map#1" => step(input: 4, output: 4)}, duration: 2.0).to_h

    assert_in_delta 2.0, hash[:rate]
    assert_equal 4, hash[:steps]["map#1"][:output]
  end

  private

  def stats(read: 0, written: 0, rejected: {}, steps: {}, duration: 1.0)
    Metacrunch::Stats.new(read:, written:, filtered: 0, rejected:, marked: {}, failed: {}, steps:, duration:)
  end

  def step(input: 0, output: 0)
    Metacrunch::StepStats.new(input:, output:, filtered: 0, rejected: 0, failed: 0, time: nil)
  end

end
