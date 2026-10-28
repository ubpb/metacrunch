# frozen_string_literal: true

module Metacrunch
  module Redis
    # A sink: writes every record as the value of a key built from it, with
    # SET (and an expiry) or DEL, chosen per record. A batch goes out
    # pipelined, in record order, in pieces of at most max_bytes; the last
    # command for a key wins. Any Redis error stops the run: SET and DEL can
    # be repeated, so the job can run again.
    class KeyWriter

      ACTIONS = [:set, :delete].freeze
      MAX_BYTES = 1024 * 1024

      # key: a template ("book:%{isbn}", KeyTemplate) or a callable that
      # returns the key of a record. action: :set, :delete or a callable that
      # returns one per record. format: :json or :string (Format). expire:
      # seconds until a key set expires.
      def initialize(connection, key:, action: :set, format: :json, expire: nil, max_bytes: MAX_BYTES)
        @connection = connection
        @key = key_option(key)
        @action = action_option(action)
        @format = Format.check!(format)
        @expire = expire_option(expire)
        @max_bytes = Options.positive_integer(max_bytes, :max_bytes)
        @client = nil
      end

      def open(_context)
        @client = connect
      end

      def write(record) = write_batch([record])

      # Records without a key, an action or a value the format can write are
      # reported in SinkFailures after the others are written.
      def write_batch(records)
        @client ||= connect
        failed = {}
        commands = []
        records.each_with_index do |record, index|
          commands << command(record)
        rescue Error => e
          failed[index] = e
        end
        Pieces.of(commands, @max_bytes) { |command| command.sum { it.to_s.bytesize } }.each { pipeline(it) }
        raise SinkFailures, failed unless failed.empty?
      end

      def close
        @client&.close
        @client = nil
      end

      def inspect
        action = @action.respond_to?(:call) ? "(callable)" : @action
        "#<#{self.class.name} key=#{described_key} action=#{action} connection=#{@connection.inspect}>"
      end

      private

      def label = "redis keys #{described_key}"

      def described_key = @key.is_a?(KeyTemplate) ? @key : "(callable)"

      def connect
        @connection.connect
      rescue Error => e
        raise OutputError, "#{label}: #{e.message}"
      end

      def pipeline(commands)
        @client.pipelined { |pipeline| commands.each { pipeline.call(*it) } }
      rescue RedisClient::Error => e
        raise OutputError, "#{label}: #{e.message}"
      end

      def command(record)
        action = action_for(record)
        key = key_for(record)
        return ["DEL", key] if action == :delete

        value = Format.encode(@format, record)
        @expire ? ["SET", key, value, "EX", @expire.to_s] : ["SET", key, value]
      end

      def action_for(record)
        return @action unless @action.respond_to?(:call)

        action = @action.call(record)
        return action if ACTIONS.include?(action)

        raise Error, "action must be :set or :delete, got #{action.inspect}"
      end

      def key_for(record)
        return @key.key(record) if @key.is_a?(KeyTemplate)

        key = @key.call(record)
        return key if key.is_a?(String) && !key.empty?

        raise Error, "key returned #{key.inspect}, not a non-empty String"
      end

      def key_option(value)
        return KeyTemplate.new(value) if value.is_a?(String) && !value.empty?
        return value if value.respond_to?(:call)

        raise ArgumentError, "key must be a template such as book:%{isbn} or a callable, got #{value.inspect}"
      end

      def action_option(value)
        return value if ACTIONS.include?(value) || value.respond_to?(:call)

        raise ArgumentError, "action must be :set, :delete or a callable, got #{value.inspect}"
      end

      def expire_option(value)
        return value if value.nil? || (value.is_a?(Integer) && value.positive?)

        raise ArgumentError, "expire must be a positive Integer of seconds, got #{value.inspect}"
      end

    end
  end
end
