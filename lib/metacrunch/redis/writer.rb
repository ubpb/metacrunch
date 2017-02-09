require "metacrunch/redis"

module Metacrunch
  class Redis::Writer

    def initialize(redis_connection_or_url, options = {})
      @save_on_close = options.delete(:save_on_close) || true

      @key = options.delete(:key) || :key

      @redis = if redis_connection_or_url.is_a?(String)
        ::Redis.new(url: redis_connection_or_url)
      else
        redis_connection_or_url
      end
    end

    def write(data)
      key = data[@key]
      raise ArgumentError, "No key found in data. Tried '#{@key}' but didn't found a value." unless key

      @redis.set(key.to_s, data.to_json)
    end

    def close
      if @redis
        @redis.bgsave if @save_on_close
        @redis.close
      end
    end

  end
end
