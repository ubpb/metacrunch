require "metacrunch/redis"

module Metacrunch
  class Redis::QueueReader
    include Metacrunch::ParallelProcessableReader

    def initialize(redis_connection_or_url, queue_name, options = {})
      @queue_name = queue_name
      raise ArgumentError, "queue_name must be a string" unless queue_name.is_a?(String)

      @blocking_mode = options.delete(:blocking) || false
      @blocking_timeout = options.delete(:blocking_timeout) || 0

      @redis = if redis_connection_or_url.is_a?(String)
        ::Redis.new(url: redis_connection_or_url)
      else
        redis_connection_or_url
      end
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      if @blocking_mode
        while true
          list, result = @redis.blpop(@queue_name, timeout: @blocking_timeout)
          if result.present?
            yield JSON.parse(result)
          else
            yield nil
          end
        end
      else
        while result = @redis.lpop(@queue_name)
          yield JSON.parse(result)
        end
      end

      self
    end

  end
end
