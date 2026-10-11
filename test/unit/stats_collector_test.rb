# frozen_string_literal: true

require "test_helper"

class StatsCollectorTest < Minitest::Test

  def test_snapshot_reports_job_and_step_counts
    collector = Metacrunch::StatsCollector.new(["map#1", "reject#2"])
    map_counter = collector.counter("map#1")
    reject_counter = collector.counter("reject#2")
    3.times do
      collector.count_read
      map_counter.input += 1
      map_counter.output += 1
      reject_counter.input += 1
    end
    collector.step_rejected("reject#2", "Patent")
    reject_counter.filtered += 1
    reject_counter.output += 1
    collector.count_written
    collector.mark("No title")
    stats = collector.snapshot

    assert_equal [3, 1, 1], [stats.read, stats.written, stats.filtered]
    assert_equal [{"Patent" => 1}, {"No title" => 1}], [stats.rejected, stats.marked]
    assert_equal Metacrunch::StepStats.new(input: 3, output: 1, filtered: 1, rejected: 1, failed: 0, time: nil),
                 stats.steps["reject#2"]
  end

  def test_failures_are_counted_by_error_class
    collector = Metacrunch::StatsCollector.new(["map#1"])
    collector.step_failed("map#1", KeyError.new("x"))
    collector.step_failed("map#1", KeyError.new("y"))

    assert_equal 2, collector.failed_total
    assert_equal({"KeyError" => 2}, collector.snapshot.failed)
  end

  def test_source_failures_are_counted_without_a_step
    collector = Metacrunch::StatsCollector.new(["map#1"])
    collector.source_failed(ArgumentError.new("unreadable"))
    stats = collector.snapshot

    assert_equal 1, collector.failed_total
    assert_equal [{"ArgumentError" => 1}, 0], [stats.failed, stats.steps["map#1"].failed]
  end

  def test_step_time_is_tracked_only_when_profiling
    plain = Metacrunch::StatsCollector.new(["map#1"])
    profiled = Metacrunch::StatsCollector.new(["map#1"], profile: true)
    profiled.step_time("map#1", 0.25)

    assert_nil plain.snapshot.steps["map#1"].time
    assert_in_delta 0.25, profiled.snapshot.steps["map#1"].time
  end

end
