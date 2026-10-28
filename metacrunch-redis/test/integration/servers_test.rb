# frozen_string_literal: true

require "test_helper"

module ServersTests

  def test_connect_says_hello_to_a_supported_server
    hello = connection.connect { it.call("HELLO", 3) }

    assert_includes ["redis", "valkey"], hello["server"]
    assert_operator Gem::Version.new(hello["version"]), :>=, Gem::Version.new("7.0")
  end

  def test_a_wrong_user_is_an_error_with_the_url
    error = assert_raises(Metacrunch::Redis::Error) { connection(user: "nosuchuser", password: "wrong").connect }

    assert_match(/\A#{Regexp.escape(target.url)}: WRONGPASS/, error.message)
  end

  def test_the_writer_warns_about_an_eviction_policy_of_the_server
    log = StringIO.new
    writer = Metacrunch::Redis::QueueWriter.new(connection, queue: key("books"))
    writer.open(context(log))

    refute_match(/evicts keys/, log.string) # the servers of the tests run with noeviction and no maxmemory
  ensure
    writer&.close
  end

end

Integration.define("Servers", ServersTests)
