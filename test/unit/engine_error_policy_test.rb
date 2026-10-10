# frozen_string_literal: true

require "test_helper"

class EngineErrorPolicyTest < Minitest::Test

  include PipelineHelper

  class RaisingSink

    def write(_record) = raise("sink broke")

  end

  class MarkingSink

    def write(_record, ctx)
      ctx.mark("too late")
    end

  end

  # recipe => expected error message, also with on_error :skip
  ALWAYS_ABORT = {
    "source" => [proc { source(Enumerator.new { raise "source broke" }) }, /source broke/],
    "id_extractor" => [proc { source([1], id: ->(_record) { raise "id broke" }) }, /id broke/],
    "sink" => [proc { source([1]); sink(RaisingSink.new) }, /sink broke/],
    "sink_changing_the_context" => [proc { source([1]); sink(MarkingSink.new) }, /read-only in sinks/],
    "before_hook" => [proc { source([1]); before { raise "hook broke" } }, /hook broke/]
  }.freeze

  def test_skip_continues_and_sends_failures_to_the_errors_sink
    target = CollectingSink.new
    failed = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map(name: "check") { it == 2 ? raise(ArgumentError, "bad") : it }
      sink target
      errors failed
      on_error :skip
    end
    failures = failed.records.zip(failed.contexts).map do |record, ctx|
      [record, ctx.failure.step, ctx.failure.error.message]
    end

    assert_equal [:ok_with_failures, [1, 3]], [result.status, target.records]
    assert_equal({"ArgumentError" => 1}, result.stats.failed)
    assert_equal [[2, "check", "bad"]], failures
  end

  def test_skip_logs_failed_records
    io = StringIO.new
    run_pipeline(logger: Metacrunch.build_logger(io)) do
      source [{"id" => "x"}], id: ->(record) { record["id"] }
      map { raise ArgumentError, "bad" }
      on_error :skip
    end

    assert_match(/ERROR \[x\] step map#1 failed at position 1 \(id x\): ArgumentError: bad/, io.string)
  end

  def test_skip_aborts_when_max_errors_is_exceeded
    result = run_pipeline do
      source [1, 2, 3, 4]
      map { raise ArgumentError, "bad" }
      on_error :skip, max_errors: 2
    end

    assert_equal [:aborted, 3], [result.status, result.stats.read]
    assert_match(/3 failed records exceed max_errors 2/, result.error.message)
    assert_instance_of Metacrunch::StepError, result.error.cause
  end

  def test_zero_max_errors_stops_at_the_first_failure_after_recording_it
    failed = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map { raise ArgumentError, "bad" }
      errors failed
      on_error :skip, max_errors: 0
    end

    assert_equal [:aborted, 1], [result.status, result.stats.read]
    assert_equal [1], failed.records
  end

  ALWAYS_ABORT.each do |description, (recipe, message)|
    define_method("test_errors_in_#{description}_abort_even_with_skip") do
      result = run_pipeline do
        instance_exec(&recipe)
        on_error :skip
      end

      assert_equal :aborted, result.status
      assert_match message, result.error.message
    end
  end

end
