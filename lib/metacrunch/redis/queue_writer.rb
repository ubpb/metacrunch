require "metacrunch/redis"

module Metacrunch
  class Redis::QueueWriter

    def initialize(redis_connection_or_url, queue_name, options = {})
      @queue_name = queue_name
      raise ArgumentError, "queue_name must be a string" unless queue_name.is_a?(String)

      @save_on_close = options.delete(:save_on_close) || true

      @redis = if redis_connection_or_url.is_a?(String)
        ::Redis.new(url: redis_connection_or_url)
      else
        redis_connection_or_url
      end
    end

    def write(data)
      @redis.rpush(@queue_name, data)
    rescue RuntimeError => e
      if e.message =~ /maxmemory/
        puts "Redis has reached maxmemory. Waiting 10 seconds and trying again..."
        sleep(10)
        retry
      else
        raise e
      end
    end

    def close
      if @redis
        @redis.bgsave if @save_on_close
        @redis.close
      end
    end

  end
end
