# frozen_string_literal: true

module Metacrunch
  module Redis
    # Sleeps in short steps, so a component that waits sees a stop (SIGTERM)
    # soon.
    module Nap

      STEP = 0.1

      module_function

      # Sleeps seconds, or until the block is true.
      def for(seconds)
        deadline = now + seconds
        sleep([STEP, deadline - now].min) while !yield && now < deadline
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    end
  end
end
