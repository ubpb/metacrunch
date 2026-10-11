# frozen_string_literal: true

require "test_helper"

class SinkOutletTest < Minitest::Test

  include PipelineHelper

  def test_writes_each_kind_to_its_sink
    target = CollectingSink.new
    rejected = CollectingSink.new
    failed = CollectingSink.new
    outlet = Metacrunch::SinkOutlet.new(build_pipeline do
      sink target
      rejects rejected
      errors failed
    end)
    outlet.deliver(1, context(1))
    outlet.reject(2, context(2))
    outlet.fail(3, failed_context(3))

    assert_equal [[1], [2], [3]], [target.records, rejected.records, failed.records]
  end

  def test_records_without_a_sink_are_dropped
    outlet = Metacrunch::SinkOutlet.new(build_pipeline { map { it } })
    outlet.deliver(1, context(1))
    outlet.reject(2, context(2))

    assert_nil outlet.fail(3, failed_context(3))
  end

  def test_failures_over_max_errors_raise_with_the_step_error_as_cause
    outlet = Metacrunch::SinkOutlet.new(build_pipeline { on_error :skip, max_errors: 1 })
    outlet.fail(1, failed_context(1))
    error = assert_raises(Metacrunch::Error) { outlet.fail(2, failed_context(2)) }

    assert_equal "2 failed records exceed max_errors 1", error.message
    assert_equal ["map#1", 2], [error.cause.step, error.cause.position]
  end

  private

  def context(position)
    Metacrunch::Context.new(id: nil, position:, logger: PipelineHelper::SILENT_LOGGER)
  end

  def failed_context(position)
    context(position).tap { it.failure = Metacrunch::Failure.new(error: ArgumentError.new("bad"), step: "map#1") }
  end

end
