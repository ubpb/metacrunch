# frozen_string_literal: true

require "test_helper"

class AuthenticationTest < Minitest::Test

  include Integration

  def test_a_wrong_password_is_explained
    error = assert_raises(Metacrunch::Elasticsearch::Error) { connection(password: "wrong").connect }

    assert_match(/\Aauthentication failed at .*; check api_key, or user and password/, error.message)
  end

  def test_an_api_key
    key = client.security.create_api_key(body: {name: @index, expiration: "1h"}).body

    begin
      es = Metacrunch::Elasticsearch::Connection.new(url: ENV.fetch("ELASTICSEARCH_URL"), api_key: key["encoded"])

      assert_kind_of Hash, es.connect.info.body
    ensure
      client.security.invalidate_api_key(body: {ids: [key["id"]]})
    end
  end

end
