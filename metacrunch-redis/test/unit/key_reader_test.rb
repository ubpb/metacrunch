# frozen_string_literal: true

require "test_helper"

class KeyReaderTest < Minitest::Test

  KeyReader = Metacrunch::Redis::KeyReader

  def setup
    @redis = FakeRedis.new
    @redis.scan_page = 2
    @connection = FakeConnection.new(@redis)
  end

  def test_constructor_checks_the_options
    {
      {match: ""} => "match must be a non-empty String, got \"\"",
      {match: nil} => "match must be a non-empty String, got nil",
      {format: :xml} => "format must be :json or :string, got :xml",
      {fetch: 0} => "fetch must be a positive Integer, got 0"
    }.each do |options, message|
      error = assert_raises(ArgumentError) { KeyReader.new(@connection, match: "book:*", **options) }

      assert_equal message, error.message
    end
  end

  def test_yields_key_and_value_for_each_matching_string_key
    @redis.call("SET", "book:1", '{"isbn":"1"}')
    @redis.call("SET", "book:2", '"two"')
    @redis.call("SET", "author:1", "{}")
    @redis.call("SET", "book:3", "3")
    @redis.call("RPUSH", "book:queue", "x")

    assert_equal [{"key" => "book:1", "value" => {"isbn" => "1"}}, {"key" => "book:2", "value" => "two"},
                  {"key" => "book:3", "value" => 3}], read
  end

  def test_scan_and_mget_per_page
    5.times { @redis.call("SET", "book:#{it}", "1") }
    read(fetch: 2)
    scan = @redis.commands.find { it.first == "SCAN" }

    assert_equal ["SCAN", "0", "MATCH", "book:*", "COUNT", 2, "TYPE", "string"], scan
    assert_equal 3, @redis.names.count("MGET")
  end

  def test_a_page_without_matching_keys_sends_no_mget
    ["author:1", "author:2", "book:1"].each { @redis.call("SET", it, "1") }

    assert_equal [{"key" => "book:1", "value" => 1}], read
    assert_equal 1, @redis.names.count("MGET")
  end

  def test_skips_keys_that_vanished_before_mget
    @redis.call("SET", "book:1", "1")
    @redis.call("SET", "book:2", "2")
    @redis.define_singleton_method(:call) do |*command|
      super(*command).then { command.first == "MGET" ? [it.first, nil] : it }
    end

    assert_equal [{"key" => "book:1", "value" => 1}], read
  end

  def test_invalid_values_are_invalid_records_with_key_and_value
    @redis.call("SET", "book:1", "{not json")
    record = read.first

    assert_kind_of Metacrunch::InvalidRecord, record
    assert_equal({"key" => "book:1", "value" => "{not json"}, record.raw)
  end

  def test_format_string_yields_the_values_as_they_are
    @redis.call("SET", "book:1", "<record/>")

    assert_equal [{"key" => "book:1", "value" => "<record/>"}], read(format: :string)
  end

  def test_redis_errors_are_input_errors
    @redis.fail_next(RedisClient::ConnectionError.new("Connection lost"), on: "SCAN")
    error = assert_raises(Metacrunch::InputError) { read }

    assert_equal "redis keys book:*: Connection lost", error.message
    assert_kind_of RedisClient::ConnectionError, error.cause
  end

  def test_an_error_of_connect_is_an_input_error
    connection = FakeConnection.new(error: Metacrunch::Redis::Error.new("redis://fake:6379/0: Connection refused"))
    error = assert_raises(Metacrunch::InputError) { KeyReader.new(connection, match: "book:*").open(context) }

    assert_equal "redis keys book:*: redis://fake:6379/0: Connection refused", error.message
  end

  def test_each_without_open_connects_and_without_a_block_is_an_enumerator
    @redis.call("SET", "book:1", "1")
    reader = KeyReader.new(@connection, match: "book:*")

    assert_equal [{"key" => "book:1", "value" => 1}], reader.each.to_a
    assert_same(reader, reader.each { nil })
  end

  def test_close_closes_the_client_and_does_nothing_without_open
    reader = KeyReader.new(@connection, match: "book:*")

    assert_nil reader.close
    reader.open(context)
    reader.close

    assert_predicate @redis, :closed?
  end

  def test_inspect_names_the_pattern_and_the_connection
    assert_equal "#<Metacrunch::Redis::KeyReader match=book:* connection=#<FakeConnection>>",
                 KeyReader.new(@connection, match: "book:*").inspect
  end

  private

  def context = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(nil))

  def read(match: "book:*", **)
    reader = KeyReader.new(@connection, match:, **)
    reader.open(context)
    reader.each.to_a
  ensure
    reader&.close
  end

end
