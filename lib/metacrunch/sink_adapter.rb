# frozen_string_literal: true

module Metacrunch
  # Wraps a sink: batching (batch: n), context passing and the optional
  # open, close and write_batch methods.
  class SinkAdapter

    # sink: the wrapped object. delivered: records the sink has accepted,
    # i.e. write or write_batch returned without raising.
    attr_reader :sink, :delivered

    def initialize(sink, batch: nil)
      raise ArgumentError, "sink must respond to #write, got #{sink.inspect}" unless sink.respond_to?(:write)
      unless batch.nil? || (batch.is_a?(Integer) && batch.positive?)
        raise ArgumentError, "batch must be a positive Integer, got #{batch.inspect}"
      end

      @sink = sink
      @batch = batch
      @write_with_context = Callable.accepts_second_argument?(sink.method(:write))
      @write_batch = sink.respond_to?(:write_batch) ? sink.method(:write_batch) : nil
      @write_batch_with_context = @write_batch && Callable.accepts_second_argument?(@write_batch)
      @records = []
      @contexts = []
      @delivered = 0
    end

    def open(context)
      @sink.open(context) if @sink.respond_to?(:open)
    end

    def write(record, ctx)
      ctx.seal!
      return write_one(record, ctx) unless @batch

      @records << record
      @contexts << ctx
      flush if @records.size >= @batch
    end

    # Writes the buffered records. The engine calls it once more before close.
    def flush
      return if @records.empty?

      @write_batch ? flush_batch : flush_one_by_one
    end

    def close
      @sink.close if @sink.respond_to?(:close)
    end

    private

    def flush_batch
      records = @records
      contexts = @contexts
      @records = []
      @contexts = []
      @write_batch_with_context ? @write_batch.call(records, contexts) : @write_batch.call(records)
      @delivered += records.size
    end

    # A record leaves the buffer only after it was written, so a flush that
    # is interrupted can be continued.
    def flush_one_by_one
      until @records.empty?
        write_one(@records.first, @contexts.first)
        @records.shift
        @contexts.shift
      end
    end

    def write_one(record, ctx)
      @write_with_context ? @sink.write(record, ctx) : @sink.write(record)
      @delivered += 1
    end

  end
end
