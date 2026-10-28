# frozen_string_literal: true

module Metacrunch
  module Redis
    # A source: takes the entries of a list from its head, the queue that
    # QueueWriter fills, fetch entries per round trip. Without wait: until the
    # queue is empty; with wait: true it waits for new entries without end,
    # with wait: seconds until none came for that long. While it waits, it
    # yields Metacrunch::FLUSH at the latest flush_after seconds after it read
    # a record, so the job writes what it holds, and it retries a lost
    # connection. stop (SIGTERM) ends it after the record under way. Entries
    # it took but did not yield go back to the head of the queue.
    class QueueReader

      FETCH = 100
      # The longest a BLMPOP waits, so the reader sees a stop or a dead
      # connection; the shortest, since 0 would block for ever.
      ROUND_TRIP = 1.0
      MIN_TIMEOUT = 0.01
      RECONNECT_DELAYS = [1, 2, 4, 8, 16, 30].freeze
      # Errors of a server that is not ready yet: it loads its data after a
      # restart, or runs a long script.
      NOT_READY = ["LOADING", "BUSY"].freeze
      # Seconds the reader tries to put entries back while Redis is full.
      PUT_BACK_PATIENCE = 10

      # queue: the key of the list. wait: false, true or seconds.
      # format: :json or :string (Format). fetch: entries per round trip.
      # flush_after: seconds, with wait:. reconnect_delays: seconds between
      # reconnects, the last one repeated; tests shorten them.
      def initialize(connection, queue:, wait: false, format: :json, fetch: FETCH, flush_after: 1,
                     reconnect_delays: RECONNECT_DELAYS)
        @connection = connection
        @queue = QueueKey.check_name!(queue)
        @wait = wait_option(wait)
        @format = Format.check!(format)
        @fetch = Options.positive_integer(fetch, :fetch)
        @flush_after = Options.seconds(flush_after, :flush_after)
        @reconnect_delays = delays_option(reconnect_delays)
        @logger = Metacrunch.logger
        @client = nil
        @stopping = false
        @taken = 0
        @left = nil
        @pending = []
      end

      def open(context)
        @logger = context.logger
        @client = connect
      end

      # Yields each record; without a block an Enumerator.
      def each(&)
        return enum_for(:each) unless block_given?

        @client ||= connect
        read(&)
        self
      end

      # The share of the queue taken so far, 0.0 to 1.0, without wait:; nil
      # before the first round trip and with wait:.
      def progress
        return nil if @wait || @left.nil?

        total = @taken + @pending.size + @left
        total.zero? ? 1.0 : @taken.fdiv(total)
      end

      # Ends each after the record under way. Called in a signal handler: it
      # only sets a flag.
      def stop
        @stopping = true
        nil
      end

      def close
        @client&.close
        @client = nil
      end

      def inspect = "#<#{self.class.name} queue=#{@queue} wait=#{@wait} connection=#{@connection.inspect}>"

      private

      def label = "redis queue #{@queue}"

      def connect
        client = @connection.connect
        QueueKey.check_type!(client, @queue)
        client
      rescue Error, RedisClient::Error => e
        raise InputError, "#{label}: #{e.message}"
      end

      def read(&)
        @taken = 0
        @left = nil
        @last_entry = now
        @unflushed_since = nil
        until @stopping
          @pending = take
          if @pending.empty?
            break unless @wait

            yield FLUSH if flush_due?
            break if quiet_too_long?

            next
          end
          hand_on(&)
          @last_entry = now
        end
      ensure
        put_back
      end

      # Yields the entries taken, one by one, until a stop; after each one a
      # FLUSH when it is due, also when the steps are slow. The quiet time of
      # wait: seconds counts from the end of the group.
      def hand_on
        until @pending.empty?
          entry = @pending.shift
          @taken += 1
          @unflushed_since ||= now if @wait
          yield Format.decode(@format, entry)
          yield FLUSH if flush_due?
          break if @stopping
        end
      end

      def flush_due?
        return false unless @unflushed_since && now - @unflushed_since >= @flush_after

        @unflushed_since = nil
        true
      end

      def quiet_too_long? = @wait.is_a?(Numeric) && now - @last_entry >= @wait

      def take = @wait ? take_waiting : take_now

      def take_now
        entries, @left = @client.pipelined do |pipeline|
          pipeline.call("LPOP", @queue, @fetch)
          pipeline.call("LLEN", @queue)
        end
        entries || []
      rescue RedisClient::Error => e
        raise InputError, "#{label}: #{e.message}"
      end

      def take_waiting
        result = reconnecting do
          timeout = round_trip_timeout
          @client.blocking_call(timeout, "BLMPOP", timeout, 1, @queue, "LEFT", "COUNT", @fetch)
        end
        result ? result.last : []
      end

      # At most ROUND_TRIP, less when the next FLUSH or the end of wait:
      # seconds is nearer.
      def round_trip_timeout
        limits = [ROUND_TRIP]
        limits << (@unflushed_since + @flush_after - now) if @unflushed_since
        limits << (@last_entry + @wait - now) if @wait.is_a?(Numeric)
        [limits.min, MIN_TIMEOUT].max.round(3)
      end

      # Retries after the reconnect delays when the connection is lost or the
      # server is not ready (it loads its data after a restart, or runs a
      # long script), until a stop (then it returns nil) or, with wait:
      # seconds, until the quiet time is over.
      def reconnecting
        lost = nil
        attempt = 0
        begin
          result = yield
          @logger.info("#{label}: going on after #{(now - lost).round} s") if lost
          result
        rescue RedisClient::Error => e
          reason = retry_reason(e)
          raise InputError, "#{label}: #{e.message}" unless reason

          lost ||= now
          raise InputError, "#{label}: gave up after #{(now - lost).round} s: #{e.message}" if quiet_too_long?

          delay = @reconnect_delays[[attempt, @reconnect_delays.size - 1].min]
          attempt += 1
          @logger.warn("#{label}: #{reason} (#{e.message}); trying again in #{delay} s")
          Nap.for(delay) { @stopping }
          retry unless @stopping
        end
      end

      def retry_reason(error)
        case error
        when RedisClient::ConnectionError, RedisClient::ProtocolError then "lost the connection"
        when RedisClient::CommandError then NOT_READY.include?(error.code) ? "the server is not ready" : nil
        end
      end

      # LPUSH e_n ... e_1 puts e_1 ... e_n back at the head, in their order.
      # While Redis is full, it tries again for a while, as other consumers
      # free memory.
      def put_back
        return if @pending.empty?

        give_up = now + put_back_patience
        begin
          @client.call_once("LPUSH", @queue, *@pending.reverse)
        rescue RedisClient::OutOfMemoryError
          raise if now >= give_up

          sleep(Nap::STEP)
          retry
        end
      rescue RedisClient::Error => e
        @logger.error("#{label}: #{@pending.size} entries taken from the queue could not be put back and are lost: " \
                      "#{e.message}")
      ensure
        @pending = []
      end

      def put_back_patience = PUT_BACK_PATIENCE

      def wait_option(value)
        return value if [true, false].include?(value) || (value.is_a?(Numeric) && value.positive?)

        raise ArgumentError, "wait must be true, false or a number of seconds above 0, got #{value.inspect}"
      end

      def delays_option(value)
        if value.is_a?(Array) && !value.empty? && value.all? { it.is_a?(Numeric) && it.positive? }
          return value.dup.freeze
        end

        raise ArgumentError, "reconnect_delays must be a non-empty Array of seconds, got #{value.inspect}"
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    end
  end
end
