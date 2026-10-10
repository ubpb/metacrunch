# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test

  include PipelineHelper

  class YieldingSource

    def each
      yield 1
      yield 2
    end

  end

  class PairSource

    def each
      yield 1, :a
      yield 2, :b
    end

  end

  # An Enumerable that skips items whose processing raises, e.g. a lenient
  # parser. It must not be able to swallow errors from later steps or sinks.
  class ForgivingEnumerable

    include Enumerable

    def each
      [1, 2].each do |item|
        yield item
      rescue StandardError
        next
      end
    end

  end

  class BrokenSink

    def write(_record) = raise(IOError, "disk full")

  end

  class RecordingObserver

    attr_reader :events

    def initialize
      @events = []
    end

    def step_in(step, record, _ctx)
      @events << [:in, step, record]
    end

    def step_out(step, outputs, _ctx)
      @events << [:out, step, outputs]
    end

  end

  class BatchSink

    attr_reader :batches

    def initialize
      @batches = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(records)
      @batches << records
    end

  end

  CONTRACT_VIOLATIONS = {
    "map_returns_nil" => proc { map { nil } },
    "flat_map_returns_a_hash" => proc { flat_map { {"a" => 1} } },
    "flat_map_returns_a_non_enumerable" => proc { flat_map { 42 } }
  }.freeze

  def test_runs_records_through_all_step_kinds
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3, 4]
      map { it * 10 }
      filter { it > 10 }
      reject { it == 40 }
      flat_map { [it, it + 1] }
      sink target
    end

    assert_equal [20, 21, 30, 31], target.records
    assert_equal :ok, result.status
  end

  def test_counts_records_per_step
    stats = run_pipeline do
      source [1, 2, 3]
      filter(&:odd?)
      flat_map { [it, it] }
      sink CollectingSink.new
    end.stats
    filter_step = stats.steps["filter#1"]

    assert_equal [3, 4, 1], [stats.read, stats.written, stats.filtered]
    assert_equal [3, 2, 1], [filter_step.input, filter_step.output, filter_step.filtered]
    assert_equal [2, 4], [stats.steps["flat_map#2"].input, stats.steps["flat_map#2"].output]
  end

  def test_reasoned_filter_and_reject_send_records_to_the_rejects_sink
    rejected = CollectingSink.new
    result = run_pipeline do
      source [{"type" => "patent"}, {"type" => "book", "public" => false}, {"type" => "book", "public" => true}]
      reject("Patent") { it["type"] == "patent" }
      filter("Not public") { it["public"] }
      rejects rejected
    end

    assert_equal({"Patent" => 1, "Not public" => 1}, result.stats.rejected)
    assert_equal([["Patent", "reject#1"], ["Not public", "filter#2"]],
                 rejected.contexts.map { [it.rejection.reason, it.rejection.step] })
  end

  def test_reject_from_the_context_stops_the_record
    later = []
    result = run_pipeline do
      source [1, 2]
      map do |record, ctx|
        ctx.reject!("Odd", value: record) if record.odd?
        record
      end
      map do |record|
        later << record
        record
      end
    end

    assert_equal [2], later
    assert_equal({"Odd" => 1}, result.stats.rejected)
  end

  def test_flat_map_children_get_their_own_context
    target = CollectingSink.new
    result = run_pipeline do
      source [{"isbns" => ["a", "b"]}], id: ->(_record) { "rec1" }
      map do |record, ctx|
        ctx.mark("Parent")
        record
      end
      flat_map { it["isbns"] }
      reject("Isbn a") { it == "a" }
      map do |record, ctx|
        ctx.mark("Child #{record}")
        record
      end
      sink target
    end

    assert_equal ["b"], target.records
    assert_equal([["rec1", 1, ["Parent", "Child b"]]],
                 target.contexts.map { [it.id, it.position, it.marks.map(&:reason)] })
    assert_equal({"Parent" => 1, "Child b" => 1}, result.stats.marked)
  end

  def test_reads_sources_that_only_yield
    target = CollectingSink.new
    run_pipeline do
      source YieldingSource.new
      sink target
    end

    assert_equal [1, 2], target.records
  end

  def test_flat_map_accepts_enumerators
    target = CollectingSink.new
    run_pipeline do
      source [2]
      flat_map { |count| Enumerator.new { |yielder| count.times { yielder << it } } }
      sink target
    end

    assert_equal [0, 1], target.records
  end

  def test_sources_yielding_several_values_produce_arrays
    target = CollectingSink.new
    run_pipeline do
      source PairSource.new
      sink target
    end

    assert_equal [[1, :a], [2, :b]], target.records
  end

  def test_flat_map_streams_children_before_its_enumerator_finishes
    target = CollectingSink.new
    result = run_pipeline do
      source [1]
      flat_map do
        Enumerator.new do |yielder|
          yielder << "first"
          raise "generator broke"
        end
      end
      sink target
    end

    assert_equal ["first"], target.records
    assert_equal [:aborted, "flat_map#1"], [result.status, result.error.step]
  end

  def test_errors_after_a_flat_map_belong_to_the_later_step
    stats = run_pipeline do
      source [1]
      flat_map { [1, 2] }
      map(name: "later") { raise "later broke" }
      on_error :skip
    end.stats

    assert_equal [0, 2], [stats.steps["flat_map#1"].failed, stats.steps["later"].failed]
  end

  def test_aborts_after_a_flat_map_name_the_later_step
    result = run_pipeline do
      source [1]
      flat_map { [1, 2] }
      map(name: "later") { raise "later broke" }
    end

    assert_equal ["later", RuntimeError], [result.error.step, result.error.cause.class]
    assert_equal 0, result.stats.steps["flat_map#1"].failed
  end

  def test_errors_after_a_flat_map_cannot_be_swallowed_by_its_enumerable
    result = run_pipeline do
      source [1]
      flat_map { ForgivingEnumerable.new }
      sink BrokenSink.new
    end

    assert_equal [:aborted, IOError, "disk full"], [result.status, result.error.class, result.error.message]
  end

  CONTRACT_VIOLATIONS.each do |description, step|
    define_method("test_contract_violation_#{description}_aborts") do
      result = run_pipeline do
        source [1]
        instance_exec(&step)
      end

      assert_equal :aborted, result.status
      assert_instance_of Metacrunch::ContractError, result.error.cause
    end
  end

  def test_step_errors_abort_with_record_details
    result = run_pipeline do
      source [{"id" => "a"}, {"id" => "b"}, {"id" => "c"}], id: ->(record) { record["id"] }
      map(name: "lookup") { it["id"] == "b" ? raise(KeyError, "boom") : it }
    end
    error = result.error

    assert_equal [:aborted, 2], [result.status, result.stats.read]
    assert_equal ["lookup", "b", 2, KeyError], [error.step, error.record_id, error.position, error.cause.class]
    assert_equal "step lookup failed at position 2 (id b): KeyError: boom", error.message
  end

  def test_flushes_sink_batches_at_the_end
    target = BatchSink.new
    run_pipeline do
      source [1, 2, 3]
      sink target, batch: 2
    end

    assert_equal [[1, 2], [3]], target.batches
  end

  def test_observer_sees_inputs_and_outputs_of_each_step
    observer = RecordingObserver.new
    pipeline = build_pipeline do
      source [1, 2]
      filter(&:odd?)
      map { it * 10 }
    end
    Metacrunch::Engine.new(pipeline, observer:).run
    expected = [[:in, "filter#1", 1], [:out, "filter#1", [1]], [:in, "map#2", 1], [:out, "map#2", [10]],
                [:in, "filter#1", 2], [:out, "filter#1", []]]

    assert_equal expected, observer.events
  end

  def test_runs_without_a_sink
    stats = run_pipeline do
      source [1, 2]
      map { it }
    end.stats

    assert_equal [2, 0, 2], [stats.read, stats.written, stats.steps["map#1"].output]
  end

end
