# frozen_string_literal: true

require "test_helper"
require "socket"

class ConnectionTest < Minitest::Test

  Connection = Metacrunch::Redis::Connection

  def test_building_a_connection_does_no_io
    connection = Connection.new(url: "redis://redis.invalid:6379/0", connect_timeout: 0.1)

    assert_equal "redis://redis.invalid:6379/0", connection.url
  end

  def test_takes_redis_rediss_and_unix_urls
    ["redis://localhost:6379/0", "rediss://host:6380/1", "unix:///tmp/redis.sock", "REDIS://host"].each do |url|
      assert_equal url, Connection.new(url:).url
    end
  end

  def test_refuses_other_urls
    ["http://host", "localhost:6379", "", nil, 6379].each do |url|
      error = assert_raises(ArgumentError) { Connection.new(url:) }

      assert_equal "url must be a Redis URL such as redis://localhost:6379/0, rediss://host:6380/1 or " \
                   "unix:///path/redis.sock, got #{url.inspect}", error.message
    end
  end

  def test_refuses_a_url_ruby_cannot_parse_and_filters_it
    error = assert_raises(ArgumentError) { Connection.new(url: "redis://u:secret@host:port/0") }

    assert_includes error.message, "redis://[FILTERED]@host:port/0"
    refute_includes error.message, "secret"
  end

  def test_refuses_user_and_password_both_in_the_url_and_as_options
    error = assert_raises(ArgumentError) { Connection.new(url: "redis://:pw@host", password: "pw") }

    assert_equal "give user and password in url or as options, not both", error.message
  end

  def test_user_and_password_must_be_non_empty_strings
    assert_raises(ArgumentError, "user must be a non-empty String") { Connection.new(url: "redis://h", user: "") }
    error = assert_raises(ArgumentError) { Connection.new(url: "redis://h", password: 1) }

    assert_equal "password must be a non-empty String", error.message
  end

  def test_refuses_options_redis_client_does_not_know
    assert_raises(ArgumentError) { Connection.new(url: "redis://h", colour: "blue") }
  end

  def test_url_and_inspect_filter_user_info
    connection = Connection.new(url: "redis://u:p%40w@host:1/0")

    assert_equal "redis://[FILTERED]@host:1/0", connection.url
    assert_equal "#<Metacrunch::Redis::Connection url=redis://[FILTERED]@host:1/0>", connection.inspect
  end

  def test_inspect_names_the_user_and_hides_the_password
    connection = Connection.new(url: "redis://host:1/0", user: "etl", password: "secret")

    assert_equal "#<Metacrunch::Redis::Connection url=redis://host:1/0 user=etl password=[FILTERED]>", connection.to_s
  end

  def test_from_params_reads_the_declared_params
    params = bound(Metacrunch::Redis::CONNECTION_PARAMS, {url: "redis://host/0", user: "etl", password: "pw"})

    assert_equal "#<Metacrunch::Redis::Connection url=redis://host/0 user=etl password=[FILTERED]>",
                 Connection.from_params(params).inspect
  end

  def test_from_params_with_a_prefix
    declarations = proc do
      use Metacrunch::Redis.connection_params("source")
      use Metacrunch::Redis.connection_params("target")
    end
    params = bound(declarations, {source_url: "redis://a/0", target_url: "redis://b/1", target_password: "pw"})

    assert_equal "redis://a/0", Connection.from_params(params, prefix: "source").url
    assert_equal "#<Metacrunch::Redis::Connection url=redis://b/1 password=[FILTERED]>",
                 Connection.from_params(params, prefix: "target").inspect
  end

  def test_connect_to_a_closed_port_raises_an_error_with_the_url_once
    port = closed_port
    connection = Connection.new(url: "redis://127.0.0.1:#{port}/0", connect_timeout: 0.5)
    error = assert_raises(Metacrunch::Redis::Error) { connection.connect }

    assert_match %r{\Aredis://127\.0\.0\.1:#{port}/0: [^/]*\z}, error.message
    assert_kind_of RedisClient::CannotConnectError, error.cause
  end

  def test_connect_returns_a_client_that_said_hello
    server = TinyServer.new
    client = Metacrunch::Redis::Connection.new(url: server.url).connect

    assert_equal "OK", client.call("PING")
    assert_includes server.commands.size.times.map { server.commands.pop }, ["HELLO", "3"]
  ensure
    client&.close
    server.stop
  end

  def test_connect_with_a_block_closes_the_client_and_returns_the_value
    server = TinyServer.new
    client = nil
    value = Metacrunch::Redis::Connection.new(url: server.url).connect do |redis|
      client = redis
      :done
    end

    assert_equal :done, value
    refute_predicate client, :connected?
  ensure
    server.stop
  end

  def test_connect_to_an_old_redis_raises_and_closes_the_client
    server = TinyServer.new(version: "6.2.14")
    error = assert_raises(Metacrunch::Redis::Error) { Metacrunch::Redis::Connection.new(url: server.url).connect }

    assert_equal "#{server.url}: Redis 6.2.14 is too old; metacrunch-redis needs Redis 7 or later, or Valkey",
                 error.message
  ensure
    server.stop
  end

  def test_redis_7_and_later_and_any_valkey_pass_the_check
    [{"server" => "redis", "version" => "7.0.0"}, {"server" => "redis", "version" => "8.10.3"},
     {"server" => "valkey", "version" => "7.2.4"}].each do |hello|
      assert_nil Connection.check_server!(hello, "redis://h")
    end
  end

  def test_an_older_redis_is_refused
    error = assert_raises(Metacrunch::Redis::Error) do
      Connection.check_server!({"server" => "redis", "version" => "6.2.14"}, "redis://h")
    end

    assert_equal "redis://h: Redis 6.2.14 is too old; metacrunch-redis needs Redis 7 or later, or Valkey", error.message
  end

  def test_a_server_without_a_version_is_refused
    assert_raises(Metacrunch::Redis::Error) { Connection.check_server!({"server" => "redis"}, "redis://h") }
  end

  private

  def bound(declarations, values)
    Metacrunch::Params.new.tap { it.use(declarations) }.bind_values(values)
  end

  def closed_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end

end
