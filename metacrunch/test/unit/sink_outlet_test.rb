# frozen_string_literal: true

require "test_helper"

class SinkOutletTest < Minitest::Test

  include PipelineHelper

  def test_writes_each_kind_to_its_sink
    target = CollectingSink.new
    rejected = CollectingSink.new
    failed = CollectingSink.new
    outlet = outlet(build_pipeline do
      sink target
      rejects rejected
      failures failed
    end)
    outlet.deliver(1, context(1))
    outlet.reject(2, context(2))
    outlet.fail(3, failed_context(3))

    assert_equal [[1], [2], [3]], [target.records, rejected.records, failed.records]
  end

  def test_records_without_a_sink_are_dropped
    outlet = outlet(build_pipeline { map { it } })
    outlet.deliver(1, context(1))
    outlet.reject(2, context(2))

    assert_nil outlet.fail(3, failed_context(3))
  end

  def test_failures_over_max_failures_raise_with_the_step_error_as_cause
    outlet = outlet(build_pipeline { on_failure :skip, max_failures: 1 })
    outlet.fail(1, failed_context(1))
    error = assert_raises(Metacrunch::Error) { outlet.fail(2, failed_context(2)) }

    assert_equal "2 failed records exceed max_failures 1", error.message
    assert_equal ["map#1", 2], [error.cause.step, error.cause.position]
  end

  def test_a_record_the_sink_did_not_write_aborts_by_default
    stats = Metacrunch::StatsCollector.new([])
    outlet = outlet(build_pipeline { sink FailingSink.new(1) }, stats:)
    error = assert_raises(Metacrunch::StepError) { outlet.deliver(1, context(1)) }

    assert_equal ["sink", 1, "bad 1"], [error.step, error.position, error.cause.message]
    assert_equal({"ArgumentError" => 1}, stats.snapshot.failed)
  end

  def test_records_the_sink_did_not_write_go_to_the_failures_sink_under_skip
    failed = CollectingSink.new
    outlet = outlet(build_pipeline do
      sink FailingSink.new(1)
      failures failed
      on_failure :skip, max_failures: 1
    end)
    outlet.deliver(1, context(1))
    error = assert_raises(Metacrunch::Error) { outlet.deliver(1, context(2)) }

    assert_equal [[1, 1], ["sink"]], [failed.records, failed.contexts.map { it.failure.step }.uniq]
    assert_equal "2 failed records exceed max_failures 1", error.message
  end

  private

  def outlet(pipeline, stats: Metacrunch::StatsCollector.new([]))
    Metacrunch::SinkOutlet.new(pipeline, stats:)
  end

  def context(position)
    Metacrunch::Context.new(id: nil, position:, logger: PipelineHelper::SILENT_LOGGER)
  end

  def failed_context(position)
    context(position).tap { it.failure = Metacrunch::Failure.new(error: ArgumentError.new("bad"), step: "map#1") }
  end

end
