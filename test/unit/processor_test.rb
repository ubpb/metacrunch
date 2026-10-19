# frozen_string_literal: true

require "test_helper"

class ProcessorTest < Minitest::Test

  include PipelineHelper

  # Notes what leaves the chain.
  class RecordingOutlet

    attr_reader :events

    def initialize
      @events = []
    end

    def deliver(record, ctx) = @events << [:deliver, record, ctx.position]

    def reject(record, ctx) = @events << [:reject, record, ctx.rejection.reason]

    def fail(record, ctx) = @events << [:fail, record, ctx.failure.step]

  end

  # A step callable that notes open and close.
  class Lifecycle

    attr_reader :log

    def initialize
      @log = []
    end

    def open(_context) = @log << :open

    def close = @log << :close

    def call(record) = record

  end

  class FailingClose

    def close = raise("close broke")

    def call(record) = record

  end

  def test_hands_what_leaves_the_chain_to_the_outlet
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map { it == 2 ? raise(ArgumentError, "bad") : it }
      reject("Three") { it == 3 }
      on_failure :skip
    end
    [1, 2, 3].each { processor.call(it, it) }

    assert_equal [[:deliver, 1, 1], [:fail, 2, "map#1"], [:reject, 3, "Three"]], outlet.events
  end

  def test_counts_in_the_given_stats
    stats = Metacrunch::StatsCollector.new(["filter#1"])
    processor = build_processor(RecordingOutlet.new, stats:) { filter(&:odd?) }
    processor.call(1, 1)
    processor.call(2, 2)

    assert_equal [2, 1], [stats.read, stats.filtered_total]
  end

  def test_opens_and_closes_each_step_callable_once
    step = Lifecycle.new
    processor = build_processor(RecordingOutlet.new) do
      map step
      map step
    end
    processor.open
    2.times { processor.close }

    assert_equal [:open, :close], step.log
  end

  def test_close_returns_the_first_error
    processor = build_processor(RecordingOutlet.new) { map FailingClose.new }
    processor.open

    assert_equal "close broke", processor.close.message
  end

  private

  def build_processor(outlet, stats: nil, &)
    pipeline = build_pipeline(&)
    stats ||= Metacrunch::StatsCollector.new(pipeline.steps.map(&:name))
    Metacrunch::Processor.new(pipeline, stats:, outlet:)
  end

end
