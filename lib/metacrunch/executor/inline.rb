# frozen_string_literal: true

module Metacrunch
  module Executor
    # Processes records one after another, in source order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work. Several values yielded
      # at once become one Array record, as with Enumerable#to_a.
      #
      # select: callable (record, position); only records it accepts are
      # yielded, positions still count every record. limit: stop after this
      # many yielded records; `break` lets the source's ensure blocks run.
      def run(source, limit: nil, select: nil)
        position = 0
        yielded = 0
        source.each do |*values|
          record = values.size <= 1 ? values.first : values
          position += 1
          next if select && !select.call(record, position)

          yield(record, position)
          break if limit && (yielded += 1) >= limit
        end
      end

    end
  end
end
