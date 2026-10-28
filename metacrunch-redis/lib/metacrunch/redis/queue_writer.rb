# frozen_string_literal: true

module Metacrunch
  module Redis
    # A sink: pushes every record as one entry to the tail of a list, a queue
    # that QueueReader takes from the head. A batch goes out as one RPUSH per
    # piece of at most max_bytes. While Redis is full (maxmemory) or the
    # queue holds max_length entries, the writer waits and tries again,
    # until a stop (SIGTERM) makes it give up the batch.
    class QueueWriter

      MAX_BYTES = 1024 * 1024

      # Raised in a pause after a stop.
      class Stopped < StandardError; end
      private_constant :Stopped

      # queue: the key of the list. format: :json or :string (Format).
      # max_length: pause while the queue holds this many entries. pause:
      # seconds between two tries while the writer waits.
      def initialize(connection, queue:, format: :json, max_length: nil, pause: 1, max_bytes: MAX_BYTES)
        @connection = connection
        @queue = QueueKey.check_name!(queue)
        @format = Format.check!(format)
        @max_length = max_length && Options.positive_integer(max_length, :max_length)
        @pause = Options.seconds(pause, :pause)
        @max_bytes = Options.positive_integer(max_bytes, :max_bytes)
        @logger = Metacrunch.logger
        @client = nil
        @paused_since = nil
        @stopping = false
      end

      def open(context)
        @logger = context.logger
        @client = connect
      end

      def write(record) = write_batch([record])

      # Records that cannot be encoded are reported in SinkFailures after the
      # others are written.
      def write_batch(records)
        @client ||= connect
        failed = {}
        entries = []
        records.each_with_index do |record, index|
          entries << Format.encode(@format, record)
        rescue Error => e
          failed[index] = e
        end
        pieces = Pieces.of(entries, @max_bytes, &:bytesize)
        pieces.each_with_index do |piece, index|
          push(piece)
        rescue Stopped
          left = pieces.drop(index).sum(&:size)
          what = left == 1 ? "1 record of the batch was" : "#{left} records of the batch were"
          raise OutputError, "#{label}: stopped while waiting for consumers; #{what} not written"
        end
        raise SinkFailures, failed unless failed.empty?
      end

      # Ends a pause: the batch it holds is not written. Called in a signal
      # handler: it only sets a flag.
      def stop
        @stopping = true
        nil
      end

      def close
        @client&.close
        @client = nil
      end

      def inspect = "#<#{self.class.name} queue=#{@queue} connection=#{@connection.inspect}>"

      private

      def label = "redis queue #{@queue}"

      # Connects, checks that the key holds a list or nothing, and warns when
      # Redis may evict the queue's entries.
      def connect
        client = @connection.connect
        QueueKey.check_type!(client, @queue)
        warn_about_eviction(client)
        client
      rescue Error, RedisClient::Error => e
        raise OutputError, "#{label}: #{e.message}"
      end

      # A refused RPUSH writes none of its entries, so it is sent again.
      # call_once: redis-client never retries it after a connection error,
      # which could write it twice.
      def push(piece)
        wait_for_room if @max_length
        @client.call_once("RPUSH", @queue, *piece)
        going_on
      rescue RedisClient::OutOfMemoryError
        pausing("Redis is full (maxmemory); waiting for consumers to take entries")
        nap
        retry
      rescue RedisClient::Error => e
        raise OutputError, "#{label}: #{e.message}"
      end

      def wait_for_room
        loop do
          length = @client.call("LLEN", @queue)
          break if length < @max_length

          pausing("the queue holds #{length} entries (max_length #{@max_length}); waiting for consumers")
          nap
        end
      end

      def nap
        raise Stopped if @stopping

        Nap.for(@pause) { @stopping }
        raise Stopped if @stopping
      end

      # Logs once when a pause begins and once when it ends.
      def pausing(reason)
        return if @paused_since

        @paused_since = now
        @logger.warn("#{label}: #{reason}")
      end

      def going_on
        return unless @paused_since

        @logger.info("#{label}: going on after #{(now - @paused_since).round} s")
        @paused_since = nil
      end

      def warn_about_eviction(client)
        info = client.call("INFO", "memory")
        policy = info[/^maxmemory_policy:(\S+)/, 1]
        return if info[/^maxmemory:(\d+)/, 1].to_i.zero? || policy.nil? || policy == "noeviction"

        @logger.warn("#{label}: Redis evicts keys when it is full (maxmemory-policy #{policy}), entries of this " \
                     "queue among them; set maxmemory-policy noeviction")
      rescue RedisClient::CommandError
        nil
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    end
  end
end
