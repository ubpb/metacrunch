# frozen_string_literal: true

require "test_helper"

class EngineMonitorTest < Minitest::Test

  include PipelineHelper

  # Notes the live counters at start and stop.
  class RecordingMonitor

    attr_reader :events, :live

    def initialize
      @events = []
    end

    def start(live)
      @live = live
      @events << [:start, live.read]
    end

    def stop
      @events << [:stop, @live.read, @live.written]
    end

  end

  def test_the_monitor_sees_the_live_counters
    monitor = RecordingMonitor.new
    pipeline = build_pipeline do
      source [1, 2, 3]
      reject("Even", &:even?)
      filter { it < 3 }
      sink CollectingSink.new
    end
    engine(pipeline, monitor:).run
    live = monitor.live

    assert_equal [[:start, 0], [:stop, 3, 1]], monitor.events
    assert_equal [1, 1, 0, nil], [live.filtered, live.rejected, live.failed, live.limit]
    assert_same pipeline.source, live.source
  end

  def test_the_monitor_stops_after_an_abort_and_a_signal
    aborted = RecordingMonitor.new
    interrupted = RecordingMonitor.new
    engine(build_pipeline { source [1]; map { raise "broken" } }, monitor: aborted).run

    assert_raises(Interrupt) do
      engine(build_pipeline { source [1]; map { raise Interrupt } }, monitor: interrupted).run
    end
    assert_equal [:start, :stop], aborted.events.map(&:first)
    assert_equal [:start, :stop], interrupted.events.map(&:first)
  end

  def test_the_monitor_knows_the_number_of_workers
    monitor = RecordingMonitor.new
    engine(build_pipeline { source [1] }, monitor:).run

    assert_equal executor.workers, monitor.live.workers
  end

  def test_failures_and_time_are_live
    monitor = RecordingMonitor.new
    pipeline = build_pipeline do
      source [1, 2]
      map { raise "broken" }
      on_failure :skip
    end
    engine(pipeline, monitor:).run

    assert_equal [2, 0], [monitor.live.failed, monitor.live.written]
    assert_operator monitor.live.elapsed, :>, 0
  end

end

ForkVariant.define(EngineMonitorTest)
