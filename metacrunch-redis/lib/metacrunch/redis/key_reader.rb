# frozen_string_literal: true

module Metacrunch
  module Redis
    # A source: the String keys that match a pattern, with their values, as
    # {"key" => key, "value" => value}. SCAN with MATCH and TYPE string, and
    # MGET per page. Redis returns every key that exists during the whole
    # scan, but may return a key twice when the database changes meanwhile.
    class KeyReader

      FETCH = 1000

      # match: a glob pattern of Redis (book:*). format: :json or :string
      # (Format). fetch: the COUNT hint of SCAN.
      def initialize(connection, match:, format: :json, fetch: FETCH)
        @connection = connection
        @match = Options.string(match, :match)
        @format = Format.check!(format)
        @fetch = Options.positive_integer(fetch, :fetch)
        @client = nil
      end

      def open(_context)
        @client = connect
      end

      # Yields each record; without a block an Enumerator. Every call reads
      # anew.
      def each(&)
        return enum_for(:each) unless block_given?

        @client ||= connect
        cursor = "0"
        loop do
          cursor, keys = scan(cursor)
          values(keys).each(&) unless keys.empty?
          break if cursor == "0"
        end
        self
      end

      def close
        @client&.close
        @client = nil
      end

      def inspect = "#<#{self.class.name} match=#{@match} connection=#{@connection.inspect}>"

      private

      def label = "redis keys #{@match}"

      def connect
        @connection.connect
      rescue Error => e
        raise InputError, "#{label}: #{e.message}"
      end

      def scan(cursor)
        redis { @client.call("SCAN", cursor, "MATCH", @match, "COUNT", @fetch, "TYPE", "string") }
      end

      # The records of the keys; a key that vanished since SCAN has no value.
      def values(keys)
        redis { @client.call("MGET", *keys) }.zip(keys).filter_map do |value, key|
          record(key, value) unless value.nil?
        end
      end

      def record(key, value)
        decoded = Format.decode(@format, value, raw: {"key" => key, "value" => value})
        decoded.is_a?(InvalidRecord) ? decoded : {"key" => key, "value" => decoded}
      end

      def redis
        yield
      rescue RedisClient::Error => e
        raise InputError, "#{label}: #{e.message}"
      end

    end
  end
end
