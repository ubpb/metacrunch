require "redis"

module Metacrunch
  class Redis
    require_relative "redis/queue_reader"
    require_relative "redis/queue_writer"
  end
end
