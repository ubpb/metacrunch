# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test

  def test_api_errors_keep_status_and_body
    error = Metacrunch::Ai::ApiError.new("refused", status: 401, body: "no key")

    assert_equal ["refused", 401, "no key"], [error.message, error.status, error.body]
  end

  def test_status_and_body_are_optional
    error = Metacrunch::Ai::Unavailable.new("no answer")

    assert_nil error.status
    assert_nil error.body
  end

  def test_the_errors_are_metacrunch_errors
    ai = Metacrunch::Ai
    parents = [ai::Error, ai::ApiError, ai::InvalidInput, ai::Unavailable].map(&:superclass)

    assert_equal [Metacrunch::Error, ai::Error, ai::ApiError, ai::ApiError], parents
  end

end
