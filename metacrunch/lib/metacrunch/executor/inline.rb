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

      # The number of processes that run steps.
      def workers = 1

      # Opens the step callables, pushes the source records (limit and
      # select applied) through them into the outlet and closes them.
      # Raises the error that stopped the records, else the first error of
      # closing.
      def run(pipeline, stats:, outlet:, observer: nil, select: nil)
        processor = Processor.new(pipeline, stats:, outlet:, observer:)
        begin
          processor.open
          flush = -> { outlet.flush }
          Inline.each_record(pipeline.source, limit: pipeline.limit, select:, flush:) do |record, position|
            processor.call(record, position)
          end
        ensure
          close_error = processor.close
        end
        raise close_error if close_error
      end

    end
  end
end
