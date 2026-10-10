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

  private

  def context(position)
    Metacrunch::Context.new(id: nil, position:, logger: Logger.new(nil))
  end

end
