# frozen_string_literal: true

require "test_helper"

class EngineInvalidRecordTest < Minitest::Test

  include PipelineHelper

  # Records step events and, at step_out, the step of ctx.failure.
  class FailureObserver

    attr_reader :events

    def initialize
      @events = []
    end

    def step_in(step, record, _ctx)
      @events << [:in, step, record]
    end

    def step_out(step, outputs, ctx)
      @events << [:out, step, outputs, ctx.failure&.step]
    end

  end

  def test_invalid_records_abort_the_run_by_default
    bad = invalid_record
    result = run_pipeline do
      source [1, bad, 3]
      map { it * 2 }
    end
    error = result.error

    assert_equal [:aborted, 2], [result.status, result.stats.read]
    assert_equal ["source", nil, 2], [error.step, error.record_id, error.position]
    assert_equal "step source failed at position 2: ArgumentError: unreadable", error.message
  end

  def test_invalid_records_go_to_the_errors_sink_under_skip
    bad = invalid_record
    target = CollectingSink.new
    failures = CollectingSink.new
    result = run_pipeline do
      source [1, bad, 3], id: ->(record) { record * 100 }
      map { it * 2 }
      sink target
      errors failures
      on_error :skip
    end

    assert_equal [:ok_with_failures, [2, 6]], [result.status, target.records]
    assert_equal ["{broken"], failures.records
    assert_equal([["source", nil, 2]], failures.contexts.map { [it.failure.step, it.id, it.position] })
  end

  def test_invalid_records_count_as_failed_without_a_step_entry
    bad = invalid_record
    result = run_pipeline do
      source [bad]
      map { it }
      on_error :skip
    end

    assert_equal({"ArgumentError" => 1}, result.stats.failed)
    assert_equal ["map#1"], result.stats.steps.keys
    assert_equal 0, result.stats.steps["map#1"].input
  end

  def test_max_errors_counts_invalid_records
    bad = invalid_record
    result = run_pipeline do
      source [bad, bad]
      on_error :skip, max_errors: 1
    end

    assert_equal :aborted, result.status
    assert_equal "2 failed records exceed max_errors 1", result.error.message
  end

  def test_the_observer_sees_invalid_records_as_the_source_step
    bad = invalid_record
    observer = FailureObserver.new
    pipeline = build_pipeline do
      source [bad]
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline, observer:).run

    assert_equal [[:in, "source", "{broken"], [:out, "source", [], "source"]], observer.events
  end

  def test_the_observer_sees_the_failure_of_a_step_under_skip
    observer = FailureObserver.new
    pipeline = build_pipeline do
      source [1]
      map { raise "broken" }
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline, observer:).run

    assert_equal [[:in, "map#1", 1], [:out, "map#1", [], "map#1"]], observer.events
  end

  private

  def invalid_record
    Metacrunch::InvalidRecord.new(raw: "{broken", error: ArgumentError.new("unreadable"))
  end

end

ForkVariant.define(
  EngineInvalidRecordTest,
  inline_only: [
    :test_the_observer_sees_invalid_records_as_the_source_step,
    :test_the_observer_sees_the_failure_of_a_step_under_skip
  ]
)
