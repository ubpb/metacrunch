# frozen_string_literal: true

module Metacrunch
  module Executor
    # Processes records one after another, in source order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work.
      def run(source)
        position = 0
        source.each { |record| yield(record, position += 1) }
      end

    end
  end
end
