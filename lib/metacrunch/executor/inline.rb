# frozen_string_literal: true

module Metacrunch
  module Executor
    # Processes records one after another, in source order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work. Several values yielded
      # at once become one Array record, as with Enumerable#to_a.
      def run(source)
        position = 0
        source.each do |*values|
          yield(values.size <= 1 ? values.first : values, position += 1)
        end
      end

    end
  end
end
