# frozen_string_literal: true

require "json"
require "redis-client"
require "metacrunch"
require_relative "redis/version"
require_relative "redis/errors"
require_relative "redis/connection"
require_relative "redis/format"
require_relative "redis/options"
require_relative "redis/pieces"
require_relative "redis/queue_key"
require_relative "redis/queue_writer"

module Metacrunch
  # Redis and Valkey for metacrunch, on redis-client: a queue between jobs
  # and a source and a sink for values under keys.
  module Redis

    PREFIX = /\A[a-z][a-z0-9_]*\z/

    # The connection params for jobs and commands, a group of parameters:
    # params { use Metacrunch::Redis.connection_params("target") }, read by
    # Connection.from_params(params, prefix: "target"). With a prefix the
    # names are target_url, target_user and target_password, for a job with
    # two servers. The password is a secret; values from environment
    # variables or the credentials come from a params file.
    def self.connection_params(prefix = nil)
      unless prefix.nil? || (prefix.is_a?(String) && prefix.match?(PREFIX))
        raise ArgumentError, "prefix must be a lowercase word such as target, got #{prefix.inspect}"
      end

      name = ->(param) { prefix ? :"#{prefix}_#{param}" : param }
      what = prefix ? "#{prefix} Redis" : "Redis"
      proc do
        param name.call(:url), String,
              required: true, desc: "#{what} URL, e.g. redis://localhost:6379/0 or rediss://host:6380/1"
        param name.call(:user), String, desc: "#{what} user"
        secret name.call(:password), String, desc: "#{what} password"
      end
    end

    # url, user and password: params { use Metacrunch::Redis::CONNECTION_PARAMS }.
    CONNECTION_PARAMS = connection_params

  end
end
