# frozen_string_literal: true

require "test_helper"

# What the other tests rely on in the stand-in for RedisClient.
class FakeRedisTest < Minitest::Test

  def setup
    @redis = FakeRedis.new
  end

  def test_blmpop_waits_for_entries_another_thread_pushes
    Thread.new do
      sleep(0.05)
      @redis.push("q", "a", "b")
    end

    assert_equal ["q", ["a", "b"]], @redis.blocking_call(1.5, "BLMPOP", 1, 1, "q", "LEFT", "COUNT", 10)
  end

  def test_blmpop_returns_nil_after_its_timeout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_nil @redis.blocking_call(0.3, "BLMPOP", 0.05, 1, "q", "LEFT", "COUNT", 10)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :>=, 0.05
  end

  def test_lists_behave_as_in_redis
    @redis.call("RPUSH", "q", "1", "2", "3")
    @redis.call("LPUSH", "q", "y", "x")

    assert_equal [["x", "y"], 3, "list"],
                 [@redis.call("LPOP", "q", 2), @redis.call("LLEN", "q"), @redis.call("TYPE", "q")]
    @redis.call("LPOP", "q", 5)

    assert_equal ["none", nil], [@redis.call("TYPE", "q"), @redis.call("LPOP", "q", 1)]
  end

  def test_fail_next_raises_for_the_named_command_only
    @redis.fail_next(RedisClient::OutOfMemoryError.new("OOM"), on: "RPUSH", times: 2)
    @redis.call("LLEN", "q")

    2.times { assert_raises(RedisClient::OutOfMemoryError) { @redis.call_once("RPUSH", "q", "a") } }

    assert_equal 1, @redis.call_once("RPUSH", "q", "a")
    assert_equal ["RPUSH", "q", "a", :once], @redis.commands.last
  end

  def test_a_list_command_on_a_string_is_a_wrong_type
    @redis.call("SET", "k", "v")

    assert_raises(RedisClient::WrongTypeError) { @redis.call("RPUSH", "k", "a") }
  end

  def test_pipelined_raises_the_first_error_after_all_commands
    @redis.fail_next(RedisClient::OutOfMemoryError.new("OOM"), on: "SET")
    assert_raises(RedisClient::OutOfMemoryError) do
      @redis.pipelined do |pipeline|
        pipeline.call("SET", "a", "1")
        pipeline.call("SET", "b", "2", "EX", 60)
      end
    end

    assert_equal [{"b" => "2"}, {"b" => 60}], [@redis.strings, @redis.expiries]
  end

  def test_scan_pages_through_matching_string_keys
    @redis.scan_page = 2
    ["book:1", "book:2", "author:1", "book:3"].each { @redis.call("SET", it, "v") }
    @redis.call("RPUSH", "book:list", "x")
    keys = []
    cursor = "0"
    loop do
      cursor, page = @redis.call("SCAN", cursor, "MATCH", "book:*", "COUNT", 2, "TYPE", "string")
      keys.concat(page)
      break if cursor == "0"
    end

    assert_equal ["book:1", "book:2", "book:3"], keys
  end

  def test_an_unknown_command_is_refused
    assert_raises(ArgumentError) { @redis.call("FLUSHALL") }
  end

end
