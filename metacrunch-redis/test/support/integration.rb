# frozen_string_literal: true

require "rbconfig"
require "securerandom"

# For the tests in test/integration: each runs against every server whose URL is set, TEST_REDIS_URL,
# TEST_REDIS_7_URL and TEST_VALKEY_URL (see test/compose.yml), and is skipped with a hint when none is.
module Integration

  Target = Data.define(:name, :url)

  SERVERS = {"redis" => "TEST_REDIS_URL", "redis_7" => "TEST_REDIS_7_URL", "valkey" => "TEST_VALKEY_URL"}.freeze
  HINT = "needs a server: set TEST_REDIS_URL, TEST_REDIS_7_URL or TEST_VALKEY_URL (see test/compose.yml)"
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def self.targets
    SERVERS.filter_map do |name, variable|
      url = ENV.fetch(variable, "")
      Target.new(name:, url:) unless url.empty?
    end
  end

  # A test class per server, named after base and the server (QueueRedis7Test), with the tests of tests; without a
  # server one class whose test is skipped with the hint.
  def self.define(base, tests)
    if targets.empty?
      Object.const_set("#{base}Test", Class.new(Minitest::Test) { define_method(:test_needs_a_server) { skip HINT } })
      return
    end

    targets.each do |target|
      test_class = Class.new(Minitest::Test) do
        include Helpers
        include tests

        define_method(:target) { target }
      end
      Object.const_set("#{base}#{target.name.split("_").map(&:capitalize).join}Test", test_class)
    end
  end

  # Every test has keys of its own (key), deleted afterwards, and a client of its own (redis).
  module Helpers

    attr_reader :redis

    def setup
      @prefix = "metacrunch-test:#{SecureRandom.hex(4)}:"
      @redis = connection.connect
      super
    end

    def teardown
      keys = []
      @redis.scan("MATCH", "#{@prefix}*") { keys << it }
      @redis.call("DEL", *keys) unless keys.empty?
      @redis.close
      super
    end

    def connection(**) = Metacrunch::Redis::Connection.new(url: target.url, **)

    def key(name) = "#{@prefix}#{name}"

    def context(log = StringIO.new) = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log))

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Waits up to seconds until the block is true; fails otherwise.
    def eventually(seconds = 10, message = "the condition never held")
      deadline = now + seconds
      until yield
        flunk(message) if now > deadline
        sleep(0.02)
      end
    end

    # Starts metacrunch run with arguments in dir, its stderr into a file there; returns the pid and the file.
    def spawn_metacrunch(*, dir:)
      log = File.join(dir, "stderr-#{SecureRandom.hex(3)}.log")
      [Process.spawn(RbConfig.ruby, BIN, "run", *, chdir: dir, in: File::NULL, out: File::NULL, err: log), log]
    end

    # The status of the process once it ended, within seconds; else it is killed and the test fails.
    def exited(pid, seconds = 30)
      deadline = now + seconds
      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        if now > deadline
          Process.kill("KILL", pid)
          Process.waitpid(pid)

          flunk("metacrunch did not end within #{seconds} s")
        end
        sleep(0.05)
      end
    end

  end

end
