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
    collector.record_failed(ArgumentError.new("unreadable"))
    stats = collector.snapshot

    assert_equal 1, collector.failed_total
    assert_equal [{"ArgumentError" => 1}, 0], [stats.failed, stats.steps["map#1"].failed]
  end

  def test_live_totals
    collector = Metacrunch::StatsCollector.new(["filter#1", "reject#2"])
    collector.count_read
    collector.counter("filter#1").filtered += 1
    collector.step_rejected("reject#2", "Patent")

    assert_equal [1, 1, 1], [collector.read, collector.filtered_total, collector.rejected_total]
    assert_operator collector.elapsed, :>=, 0
  end

  def test_take_returns_the_counts_so_far_and_starts_again
    collector = Metacrunch::StatsCollector.new(["map#1"])
    counter = collector.counter("map#1")
    collector.count_read
    counter.input += 1
    collector.mark("Odd")
    first = collector.take
    collector.count_read
    second = collector.take

    assert_equal [1, 1, {"Odd" => 1}], [first.read, first.steps["map#1"].input, first.marked]
    assert_equal [1, 0, {}], [second.read, second.steps["map#1"].input, second.marked]
    assert_same counter, collector.counter("map#1")
  end

  def test_absorb_adds_the_counts_of_another_collector
    worker = Metacrunch::StatsCollector.new(["reject#1"], profile: true)
    worker.count_read
    worker.step_rejected("reject#1", "Patent")
    worker.step_failed("reject#1", KeyError.new("x"))
    worker.step_time("reject#1", 0.5)
    parent = Metacrunch::StatsCollector.new(["reject#1"], profile: true)
    2.times { parent.absorb(worker.snapshot) }
    stats = parent.snapshot

    assert_equal [2, {"Patent" => 2}, {"KeyError" => 2}], [stats.read, stats.rejected, stats.failed]
    assert_equal [2, 2], [parent.rejected_total, parent.failed_total]
    assert_in_delta 1.0, stats.steps["reject#1"].time
  end

  def test_step_time_is_tracked_only_when_profiling
    plain = Metacrunch::StatsCollector.new(["map#1"])
    profiled = Metacrunch::StatsCollector.new(["map#1"], profile: true)
    profiled.step_time("map#1", 0.25)

    assert_nil plain.snapshot.steps["map#1"].time
    assert_in_delta 0.25, profiled.snapshot.steps["map#1"].time
  end

end
