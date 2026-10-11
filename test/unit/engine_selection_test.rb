# frozen_string_literal: true

require "test_helper"

class EngineSelectionTest < Minitest::Test

  include PipelineHelper

  # Counts the records it yields and notes when its each has ended.
  class TrackingSource

    attr_reader :yielded, :finished

    def initialize(records)
      @records = records
      @yielded = 0
      @finished = false
    end

    def each
      @records.each do |record|
        @yielded += 1
        yield record
      end
    ensure
      @finished = true
    end

  end

  def test_limit_stops_after_n_source_records
    tracking = TrackingSource.new([1, 2, 3, 4])
    target = CollectingSink.new
    pipeline = build_pipeline do
      source tracking
      sink target
    end
    result = engine(pipeline.with(limit: 2)).run

    assert_equal [:ok, [1, 2]], [result.status, target.records]
    assert_equal [2, true], [tracking.yielded, tracking.finished]
  end

  def test_limit_counts_source_records_not_flat_map_outputs
    target = CollectingSink.new
    pipeline = build_pipeline do
      source [1, 2]
      flat_map { [it, it] }
      sink target
    end
    engine(pipeline.with(limit: 1)).run

    assert_equal [1, 1], target.records
  end

  def test_select_skips_records_without_processing_them
    target = CollectingSink.new
    seen = []
    pipeline = build_pipeline do
      source ["a", "b", "c"]
      map(&:upcase)
      sink target
    end
    select = lambda do |record, position|
      seen << [record, position]
      position != 2
    end
    result = engine(pipeline, select:).run

    assert_equal ["A", "C"], target.records
    assert_equal [["a", 1], ["b", 2], ["c", 3]], seen
    assert_equal 2, result.stats.read
  end

  def test_limit_counts_selected_records
    tracking = TrackingSource.new((1..10).to_a)
    target = CollectingSink.new
    pipeline = build_pipeline do
      source tracking
      sink target
    end
    engine(pipeline.with(limit: 2), select: ->(_record, position) { position.even? }).run

    assert_equal [[2, 4], 4], [target.records, tracking.yielded]
  end

  def test_invalid_limits_are_rejected
    pipeline = build_pipeline { source [1] }
    error = assert_raises(ArgumentError) { engine(pipeline.with(limit: 0)).run }

    assert_equal "limit must be a positive Integer, got 0", error.message
  end

end

ForkVariant.define(EngineSelectionTest)
