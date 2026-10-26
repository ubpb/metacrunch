# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test

  Errors = Elastic::Transport::Transport::Errors
  BulkItemError = Metacrunch::Elasticsearch::BulkItemError

  def test_bulk_item_errors_name_status_reason_action_and_id
    error = BulkItemError.new(status: 400, type: "document_parsing_exception", reason: "failed to parse field [year]",
                              action: :index, id: "7")

    assert_equal "400 document_parsing_exception: failed to parse field [year] (index 7)", error.message
    assert_equal [400, :index, "7"], [error.status, error.action, error.id]
  end

  def test_bulk_item_errors_without_id
    error = BulkItemError.new(status: 400, type: "x", reason: "y", action: :create, id: nil)

    assert_equal "400 x: y (create)", error.message
  end

  def test_status_and_reason_of_server_errors
    body = JSON.generate(error: {type: "index_not_found_exception", reason: "no such index [books]"})
    error = Errors::NotFound.new("[404] #{body}")

    assert_equal 404, Metacrunch::Elasticsearch.status(error)
    assert_equal "404 index_not_found_exception: no such index [books]", Metacrunch::Elasticsearch.reason(error)
  end

  def test_reason_of_answers_that_are_not_elasticsearch_s_json
    assert_equal "502 <html>Bad Gateway</html>", reason(Errors::BadGateway.new("[502] <html>Bad Gateway</html>"))
    assert_equal "400 Incorrect HTTP method", reason(Errors::BadRequest.new('[400] {"error":"Incorrect HTTP method"}'))
    assert_equal "404", reason(Errors::NotFound.new("[404] "))
  end

  def test_errors_without_a_response_have_no_status
    assert_nil Metacrunch::Elasticsearch.status(Elastic::Transport::Transport::Error.new("Connection refused"))
    assert_nil Metacrunch::Elasticsearch.status(Errors::NotFound.new("no status in the message"))
  end

  private

  def reason(error) = Metacrunch::Elasticsearch.reason(error)

end
