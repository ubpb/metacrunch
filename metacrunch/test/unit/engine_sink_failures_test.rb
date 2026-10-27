# frozen_string_literal: true

require "test_helper"

class EngineSinkFailuresTest < Minitest::Test

  include PipelineHelper

  def test_records_the_sink_did_not_write_abort_the_run_by_default
    target = FailingSink.new(4)
    result = run_pipeline do
      source [1, 2, 3]
      map { it * 2 }
      sink target
    end
    error = result.error

    assert_equal [:aborted, [2], 1], [result.status, target.records, result.stats.written]
    assert_equal "step sink failed at position 2: ArgumentError: bad 4", error.message
  end

  def test_records_the_sink_did_not_write_go_to_the_failures_sink_under_skip
    target = FailingSink.new(4)
    failures = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3], id: ->(record) { "r#{record}" }
      map { it * 2 }
      sink target, batch: 2
      failures failures
      on_failure :skip
    end

    assert_equal [:ok_with_failures, [2, 6], [4]], [result.status, target.records, failures.records]
    assert_equal([["sink", "r2", 2]], failures.contexts.map { [it.failure.step, it.id, it.position] })
  end

  def test_failures_reported_by_the_last_flush_count_and_reach_the_failures_sink
    failures = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      sink FailingSink.new(1, 3), batch: 10
      failures failures
      on_failure :skip
    end
    stats = result.stats

    assert_equal [1, 3], failures.records
    assert_equal [1, {"ArgumentError" => 2}, {}], [stats.written, stats.failed, stats.steps]
  end

  def test_a_flush_after_an_abort_logs_the_sink_s_failure_and_keeps_the_run_s_error
    log = StringIO.new
    target = FailingSink.new(1)
    result = run_pipeline(logger: Logger.new(log)) do
      source [1, 2, 3]
      map { it == 3 ? raise(ArgumentError, "step") : it }
      sink target, batch: 10
    end

    assert_equal [:aborted, "map#1", [2]], [result.status, result.error.step, target.records]
    assert_match "flushing FailingSink after abort failed: Metacrunch::StepError: step sink failed", log.string
  end

  def test_a_flush_after_an_abort_sends_the_sink_s_failures_to_the_failures_sink
    failures = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map { it == 3 ? raise(ArgumentError, "step") : it }
      sink FailingSink.new(1), batch: 10
      failures failures
      on_failure :skip, max_failures: 0
    end

    assert_equal [:aborted, [3, 1]], [result.status, failures.records]
  end

  def test_the_failures_sink_cannot_report_failed_records
    result = run_pipeline do
      source [1, 2]
      map { it == 2 ? raise(ArgumentError, "step") : it }
      failures FailingSink.new(2)
      on_failure :skip
    end

    assert_equal :aborted, result.status
    assert_instance_of Metacrunch::SinkFailures, result.error
  end

end

ForkVariant.define(EngineSinkFailuresTest)
