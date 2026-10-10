# frozen_string_literal: true

module Metacrunch
  # Wraps a sink: batching (batch: n), context passing and the optional
  # open, close and write_batch methods.
  class SinkAdapter

    attr_reader :sink

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

      records = @records
      contexts = @contexts
      @records = []
      @contexts = []
      if @write_batch
        @write_batch_with_context ? @write_batch.call(records, contexts) : @write_batch.call(records)
      else
        records.zip(contexts) { |record, ctx| write_one(record, ctx) }
      end
    end

    def close
      @sink.close if @sink.respond_to?(:close)
    end

    private

    def write_one(record, ctx)
      @write_with_context ? @sink.write(record, ctx) : @sink.write(record)
    end

  end
end
