# frozen_string_literal: true

require "test_helper"

class SinkAdapterTest < Minitest::Test

  class PlainSink

    attr_reader :written

    def initialize
      @written = []
    end

    def write(record)
      @written << record
    end

  end

  class ContextSink

    attr_reader :written

    def initialize
      @written = []
    end

    def write(record, ctx)
      @written << [record, ctx.position]
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

  class BatchContextSink

    attr_reader :positions

    def initialize
      @positions = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(_records, contexts)
      @positions << contexts.map(&:position)
    end

  end

  def test_writes_records_one_by_one_without_batch
    sink = PlainSink.new
    adapter = Metacrunch::SinkAdapter.new(sink)
    adapter.write("a", context(1))
    adapter.write("b", context(2))

    assert_equal ["a", "b"], sink.written
  end

  def test_passes_the_context_to_sinks_that_accept_it
    sink = ContextSink.new
    Metacrunch::SinkAdapter.new(sink).write("a", context(5))

    assert_equal [["a", 5]], sink.written
  end

  def test_batches_and_flushes_the_rest
    sink = BatchSink.new
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 2)
    ["a", "b", "c"].each_with_index { |record, index| adapter.write(record, context(index + 1)) }
    before_flush = sink.batches.dup
    adapter.flush

    assert_equal [["a", "b"]], before_flush
    assert_equal [["a", "b"], ["c"]], sink.batches
  end

  def test_falls_back_to_write_without_write_batch
    sink = PlainSink.new
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 10)
    adapter.write("a", context(1))
    adapter.write("b", context(2))
    before_flush = sink.written.dup
    adapter.flush

    assert_empty before_flush
    assert_equal ["a", "b"], sink.written
  end

  def test_passes_contexts_to_write_batch_that_accepts_them
    sink = BatchContextSink.new
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 2)
    adapter.write("a", context(1))
    adapter.write("b", context(2))

    assert_equal [[1, 2]], sink.positions
  end

  def test_seals_contexts_given_to_sinks
    ctx = context(1)
    Metacrunch::SinkAdapter.new(PlainSink.new).write("a", ctx)

    assert_raises(Metacrunch::ContractError) { ctx.mark("late") }
  end

  def test_forwards_open_and_close_when_defined
    events = []
    sink = Object.new
    sink.define_singleton_method(:write) { |_record| nil }
    sink.define_singleton_method(:open) { |context| events << [:open, context] }
    sink.define_singleton_method(:close) { events << :close }
    adapter = Metacrunch::SinkAdapter.new(sink)
    adapter.open(:context)
    adapter.close

    assert_equal [[:open, :context], :close], events
  end

  def test_open_and_close_are_optional
    adapter = Metacrunch::SinkAdapter.new(PlainSink.new)

    assert_nil adapter.open(:context)
    assert_nil adapter.close
  end

  def test_rejects_invalid_sinks_and_batch_sizes
    assert_raises(ArgumentError) { Metacrunch::SinkAdapter.new(Object.new) }
    assert_raises(ArgumentError) { Metacrunch::SinkAdapter.new(PlainSink.new, batch: 0) }
  end

  def test_hands_records_reported_in_a_batch_to_the_failure_handler
    sink = FailingSink.new("b")
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 3)
    reported = handle_failures(adapter)
    ["a", "b", "c"].each_with_index { |record, index| adapter.write(record, context(index + 1)) }

    assert_equal [["b", 2, "bad b"]], reported
    assert_equal [["a", "c"], 2], [sink.records, adapter.delivered]
  end

  def test_hands_a_record_reported_by_write_to_the_failure_handler
    adapter = Metacrunch::SinkAdapter.new(FailingSink.new("a"))
    reported = handle_failures(adapter)
    adapter.write("a", context(1))
    adapter.write("b", context(2))

    assert_equal [["a", 1, "bad a"]], reported
    assert_equal 1, adapter.delivered
  end

  def test_a_reported_record_leaves_the_buffer_before_the_handler_runs
    sink = Object.new
    written = []
    sink.define_singleton_method(:write) do |record|
      raise Metacrunch::SinkFailures, {0 => ArgumentError.new("bad")} if record == "a"

      written << record
    end
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 5)
    adapter.failure_handler = ->(*) { raise "abort" }
    adapter.write("a", context(1))
    adapter.write("b", context(2))
    assert_raises(RuntimeError) { adapter.flush }
    adapter.flush

    assert_equal [["b"], 1], [written, adapter.delivered]
  end

  def test_sink_failures_pass_through_without_a_failure_handler
    batched = Metacrunch::SinkAdapter.new(FailingSink.new("a"), batch: 1)

    assert_raises(Metacrunch::SinkFailures) { Metacrunch::SinkAdapter.new(FailingSink.new("a")).write("a", context(1)) }
    assert_raises(Metacrunch::SinkFailures) { batched.write("a", context(1)) }
  end

  def test_an_index_outside_the_batch_breaks_the_contract
    sink = Object.new
    sink.define_singleton_method(:write) { |_record| raise Metacrunch::SinkFailures, {1 => ArgumentError.new("bad")} }
    adapter = Metacrunch::SinkAdapter.new(sink)
    handle_failures(adapter)
    error = assert_raises(Metacrunch::ContractError) { adapter.write("a", context(1)) }

    assert_equal "Object reported index 1 in SinkFailures for 1 records", error.message
  end

  private

  def context(position)
    Metacrunch::Context.new(id: nil, position:, logger: Logger.new(nil))
  end

  # Collects [record, position, error message] of every record the sink
  # reports as not written.
  def handle_failures(adapter)
    [].tap do |reported|
      adapter.failure_handler = ->(record, ctx, error) { reported << [record, ctx.position, error.message] }
    end
  end

end
