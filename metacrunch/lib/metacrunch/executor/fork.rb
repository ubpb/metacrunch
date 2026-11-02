# frozen_string_literal: true

module Metacrunch
  module Executor
    # Runs the steps in forked worker processes; the source and the sinks
    # stay in this process. Batch k of the source goes to worker k mod N,
    # and the results are applied in the same order. A batch is a segment
    # (Executor.segment_size), at whose end the batch steps run, as inline,
    # so records, logs and failures reach the sinks in the order they do
    # inline. See Run, Worker, Frame and Dump.
    class Fork

      BATCH_SIZE = Executor::BATCH_SIZE

      # Seconds stopped workers get to close their steps before SIGKILL.
      STOP_TIMEOUT = 5

      # False on platforms without fork (Windows, JRuby).
      def self.supported? = Process.respond_to?(:fork)

      attr_reader :workers, :batch_size

      # workers: the number of worker processes, at least 2 (1 is Inline).
      # stop_timeout: see STOP_TIMEOUT; tests shorten it.
      def initialize(workers:, batch_size: BATCH_SIZE, stop_timeout: STOP_TIMEOUT)
        unless workers.is_a?(Integer) && workers >= 2
          raise ArgumentError, "workers must be an Integer of at least 2, got #{workers.inspect}"
        end

        Executor.check_batch_size!(batch_size)
        raise ArgumentError, "workers need Process.fork, which this platform lacks" unless Fork.supported?

        @workers = workers
        @batch_size = batch_size
        @stop_timeout = stop_timeout
      end

      # Like Inline#run, with the steps in the workers. Engine refuses an
      # observer before.
      def run(pipeline, stats:, outlet:, observer: nil, select: nil)
        raise ArgumentError, "an observer needs the inline executor" if observer

        segment = Executor.segment_size(pipeline, batch_size)
        Run.new(pipeline, workers:, batch_size: segment, stop_timeout: @stop_timeout, stats:, outlet:, select:).call
      end

    end
  end
end
