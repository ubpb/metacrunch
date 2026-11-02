# frozen_string_literal: true

module Metacrunch
  module Executor
    # Runs the steps in this process, one record after another, in source
    # order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work. Several values yielded
      # at once become one Array record, as with Enumerable#to_a.
      #
      # select: callable (record, position); only records it accepts are
      # yielded, positions still count every record. limit: stop after this
      # many yielded records; `break` lets the source's ensure blocks run.
      # flush: called for each FLUSH the source yields, which is no record.
      def self.each_record(source, limit: nil, select: nil, flush: nil)
        position = 0
        yielded = 0
        source.each do |*values|
          record = values.size <= 1 ? values.first : values
          next flush&.call if record.equal?(FLUSH)

          position += 1
          next if select && !select.call(record, position)

          yield(record, position)
          break if limit && (yielded += 1) >= limit
        end
      end

      attr_reader :batch_size

      # batch_size: the base of the segments after which the batch steps
      # run (Executor.segment_size), as Fork's transport batches.
      def initialize(batch_size: BATCH_SIZE)
        Executor.check_batch_size!(batch_size)
        @batch_size = batch_size
      end

      # The number of processes that run steps.
      def workers = 1

      # Opens the step callables, pushes the source records (limit and
      # select applied) through them into the outlet and closes them. The
      # batch steps run on what they hold at the end of every segment: after
      # segment_size records, at a FLUSH (before the sinks flush) and at the
      # end of the source. Raises the error that stopped the records, else
      # the first error of closing.
      def run(pipeline, stats:, outlet:, observer: nil, select: nil)
        processor = Processor.new(pipeline, stats:, outlet:, observer:)
        begin
          processor.open
          push(pipeline, processor, outlet, select)
        ensure
          close_error = processor.close
        end
        raise close_error if close_error
      end

      private

      def push(pipeline, processor, outlet, select)
        segment = Executor.segment_size(pipeline, @batch_size)
        count = 0
        flush = lambda do
          processor.flush
          count = 0
          outlet.flush
        end
        Inline.each_record(pipeline.source, limit: pipeline.limit, select:, flush:) do |record, position|
          processor.call(record, position)
          next unless (count += 1) == segment

          count = 0
          processor.flush
        end
        processor.flush
      end

    end
  end
end
