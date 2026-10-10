# frozen_string_literal: true

require "test_helper"

class EngineLifecycleTest < Minitest::Test

  include PipelineHelper

  # Can act as source, step and sink. Logs open and close.
  class Component

    attr_reader :context

    def initialize(name, log, records: [1])
      @name = name
      @log = log
      @records = records
    end

    def open(context)
      @context = context
      @log << "open #{@name}"
    end

    def close
      @log << "close #{@name}"
    end

    def each(&)
      @records.each(&)
    end

    def call(record) = record

    def write(_record) = nil

  end

  class FailingClose

    def write(_record) = nil

    def close = raise("close broke")

  end

  class FailingOpen

    def write(_record) = nil

    def open(_context) = raise("open broke")

  end

  def test_opens_components_in_order_and_closes_them_in_reverse
    log = []
    run_pipeline do
      source Component.new("source", log)
      map Component.new("step", log)
      sink Component.new("sink", log)
      rejects Component.new("rejects", log)
    end
    expected = ["open source", "open step", "open sink", "open rejects",
                "close rejects", "close sink", "close step", "close source"]

    assert_equal expected, log
  end

  def test_open_receives_params_and_logger
    component = Component.new("source", [])
    run_pipeline(params: {index: "books"}) do
      params { param :index }
      source component
    end

    assert_equal "books", component.context.params.index
    assert_same PipelineHelper::SILENT_LOGGER, component.context.logger
  end

  def test_hooks_run_around_the_records
    log = []
    run_pipeline do
      source Component.new("source", log)
      map do |record|
        log << "record #{record}"
        record
      end
      before { log << "before" }
      after { |result| log << "after #{result.status} #{result.stats.read}" }
    end

    assert_equal ["open source", "before", "record 1", "close source", "after ok 1"], log
  end

  def test_closes_components_after_an_abort
    log = []
    result = run_pipeline do
      source Component.new("source", log, records: [1, 2])
      map { it == 2 ? raise("boom") : it }
      sink Component.new("sink", log), batch: 10
    end

    assert_equal :aborted, result.status
    assert_equal ["open source", "open sink", "close sink", "close source"], log
  end

  def test_interrupt_in_a_step_closes_components_and_skips_after_hooks
    log = []
    pipeline = build_pipeline do
      source Component.new("source", log)
      map { raise Interrupt }
      after { log << "after" }
    end

    assert_raises(Interrupt) { Metacrunch::Engine.new(pipeline).run }
    assert_equal ["open source", "close source"], log
  end

  def test_interrupt_in_the_source_closes_the_sink
    log = []
    pipeline = build_pipeline do
      source(Enumerator.new { raise Interrupt })
      sink Component.new("sink", log)
    end

    assert_raises(Interrupt) { Metacrunch::Engine.new(pipeline).run }
    assert_equal ["open sink", "close sink"], log
  end

  def test_open_errors_abort_and_close_what_was_opened
    log = []
    result = run_pipeline do
      source Component.new("source", log)
      sink FailingOpen.new
    end

    assert_equal [:aborted, "open broke"], [result.status, result.error.message]
    assert_equal ["open source", "close source"], log
  end

  def test_close_errors_abort_the_run_after_closing_everything
    log = []
    result = run_pipeline do
      source Component.new("source", log)
      sink FailingClose.new
    end

    assert_equal [:aborted, "close broke"], [result.status, result.error.message]
    assert_equal ["open source", "close source"], log
  end

  def test_failing_after_hook_aborts_the_run
    seen = []
    result = run_pipeline do
      source [1]
      after { raise "report broke" }
      after { |res| seen << res.status }
    end

    assert_equal [:aborted, "report broke"], [result.status, result.error.message]
    assert_equal [:aborted], seen
  end

  def test_profile_records_time_per_step
    result = run_pipeline do
      source [1]
      map { it }
      profile true
    end

    assert_kind_of Float, result.stats.steps["map#1"].time
  end

end
