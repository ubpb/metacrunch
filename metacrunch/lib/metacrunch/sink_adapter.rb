# frozen_string_literal: true

module Metacrunch
  # Wraps a sink: batching (batch: n), context passing and the optional
  # open, close and write_batch methods.
  class SinkAdapter

    # sink: the wrapped object. delivered: records the sink has accepted,
    # i.e. write or write_batch returned without raising, less those it
    # reported in SinkFailures. batch: the batch size or nil.
    attr_reader :sink, :delivered, :batch

    # Called with record, context and error for every record the sink
    # reports in SinkFailures, in batch order. SinkOutlet sets it for the
    # job's sink; without it, SinkFailures passes through and aborts the run.
    attr_writer :failure_handler

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
      @failure_handler = nil
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
      failures = put_batch(records, contexts)
      report(failures, records, contexts) if failures
    end

    # A record leaves the buffer only after it was written or reported as
    # not written, so a flush that is interrupted can be continued.
    def flush_one_by_one
      until @records.empty?
        record = @records.first
        ctx = @contexts.first
        failures = put(record, ctx)
        @records.shift
        @contexts.shift
        report(failures, [record], [ctx]) if failures
      end
    end

    def write_one(record, ctx)
      failures = put(record, ctx)
      report(failures, [record], [ctx]) if failures
    end

    # Writes one record. Returns the SinkFailures the sink raised, or nil.
    def put(record, ctx)
      @write_with_context ? @sink.write(record, ctx) : @sink.write(record)
      @delivered += 1
      nil
    rescue SinkFailures => e
      raise unless @failure_handler

      e
    end

    def put_batch(records, contexts)
      @write_batch_with_context ? @write_batch.call(records, contexts) : @write_batch.call(records)
      @delivered += records.size
      nil
    rescue SinkFailures => e
      raise unless @failure_handler

      e
    end

    # Counts the records the sink wrote and hands the reported ones to the
    # failure handler.
    def report(failures, records, contexts)
      last = failures.failed.keys.last
      if last >= records.size
        raise ContractError, "#{@sink.class} reported index #{last} in SinkFailures for #{records.size} records"
      end

      @delivered += records.size - failures.failed.size
      failures.failed.each { |index, error| @failure_handler.call(records[index], contexts[index], error) }
    end

  end
end
