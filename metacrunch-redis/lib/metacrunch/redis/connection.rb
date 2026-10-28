# frozen_string_literal: true

module Metacrunch
  module Redis
    # Where and how to reach a Redis or Valkey server. A value: building one
    # does no I/O. Every reader and writer opens a client of its own from it
    # (connect), so a reader and a writer of one job (two threads with -w)
    # share no connection.
    class Connection

      SCHEME = %r{\A(?:redis|rediss|unix)://}i
      PARAMS = [:url, :user, :password].freeze
      # BLMPOP came with Redis 7.0; Valkey began as a fork of Redis 7.2.
      MIN_VERSION = Gem::Version.new("7.0")
      # What redis-client appends to its messages: " (redis://host:6379)".
      SERVER_URL = %r{ \((?:redis|rediss|unix)://[^)]*\)\z}

      # A connection from the bound params of a job or command: the ones of
      # Redis.connection_params(prefix) it declares.
      def self.from_params(params, prefix: nil)
        names = PARAMS.to_h { [it, prefix ? :"#{prefix}_#{it}" : it] }
        new(**names.select { |_, name| params.respond_to?(name) }.transform_values { params.public_send(it) })
      end

      # A URL for messages: user info (user:password@) as [FILTERED], up to the
      # last @, since a password may hold an unencoded @.
      def self.filter(url) = url.to_s.sub(%r{//.*@}, "//[FILTERED]@")

      # Raises Error unless the answer of HELLO comes from Valkey or from
      # Redis 7.0 or later.
      def self.check_server!(hello, url)
        return if hello["server"] == "valkey"

        version = hello["version"].to_s
        return if Gem::Version.correct?(version) && !version.empty? && Gem::Version.new(version) >= MIN_VERSION

        raise Error, "#{url}: Redis #{version} is too old; metacrunch-redis needs Redis 7 or later, or Valkey"
      end

      # url: redis://host:port/db, rediss:// (TLS) or unix:///path. user and
      # password override nothing: with user info in the URL they are an
      # error. options go to RedisClient.config (connect_timeout:,
      # read_timeout:, ssl_params:, id:, driver:, ...).
      def initialize(url:, user: nil, password: nil, **options)
        @url = redis_url(url)
        @user = optional_string(user, :user)
        @password = optional_string(password, :password)
        if (@user || @password) && @url.match?(%r{\A[^/]*//[^/]*@})
          raise ArgumentError, "give user and password in url or as options, not both"
        end

        @config = client_config(options)
      end

      # The URL for messages, user info filtered.
      def url = Connection.filter(@url)

      # A new RedisClient, checked: it says HELLO, so a wrong host or
      # password fails here, and the server must be Valkey or Redis 7 or
      # later. With a block, it yields the client, closes it afterwards and
      # returns the block's value. Raises Error.
      def connect
        client = open_client
        return client unless block_given?

        begin
          yield client
        ensure
          client.close
        end
      end

      def inspect
        parts = ["url=#{url}"]
        parts << "user=#{@user}" if @user
        parts << "password=[FILTERED]" if @password
        "#<#{self.class.name} #{parts.join(" ")}>"
      end

      alias to_s inspect

      private

      # redis-client connects at the first command.
      def open_client
        client = @config.new_client
        check(client)
        client
      end

      def check(client)
        Connection.check_server!(client.call("HELLO", 3), url)
      rescue RedisClient::Error => e
        client.close
        raise Error, "#{url}: #{e.message.sub(SERVER_URL, "")}"
      rescue Error
        client.close
        raise
      end

      def client_config(options)
        RedisClient.config(url: @url, **{username: @user, password: @password}.compact, **options)
      rescue URI::InvalidURIError => e
        raise ArgumentError, "url is no valid URL (#{url}): #{e.message.gsub(@url, url)}"
      end

      def redis_url(value)
        return value if value.is_a?(String) && value.match?(SCHEME)

        shown = value.is_a?(String) ? Connection.filter(value) : value
        raise ArgumentError, "url must be a Redis URL such as redis://localhost:6379/0, rediss://host:6380/1 or " \
                             "unix:///path/redis.sock, got #{shown.inspect}"
      end

      def optional_string(value, name)
        return value if value.nil? || (value.is_a?(String) && !value.empty?)

        raise ArgumentError, "#{name} must be a non-empty String"
      end

    end
  end
end
