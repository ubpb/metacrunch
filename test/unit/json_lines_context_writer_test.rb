# frozen_string_literal: true

require "test_helper"

class JsonLinesContextWriterTest < Minitest::Test

  # A record that is not a JSON type.
  class Opaque

    def inspect = "#<Opaque>"

  end

  def setup
    @ctx = Metacrunch::Context.new(id: 18, position: 2, logger: Logger.new(nil))
  end

  def test_writes_rejected_records_with_their_context
    @ctx.step = "map#3"
    @ctx.mark("No title")
    @ctx.step = "reject#4"
    @ctx.reject!("Not public", value: false)
    expected = {
      "record" => {"_id" => 18}, "id" => 18, "position" => 2,
      "marks" => [{"reason" => "No title", "step" => "map#3", "value" => nil}],
      "rejection" => {"reason" => "Not public", "step" => "reject#4", "value" => false}
    }

    assert_equal expected, JSON.parse(write({"_id" => 18}))
  end

  def test_writes_failures
    @ctx.failure = Metacrunch::Failure.new(error: JSON::ParserError.new("unexpected end of input"), step: "source")

    assert_equal({"step" => "source", "error" => "JSON::ParserError", "message" => "unexpected end of input"},
                 JSON.parse(write("{\"id\": 47"))["failure"])
  end

  def test_writes_values_that_are_not_json_as_inspect_strings
    @ctx.mark("Odd", value: Time.at(0).utc)
    data = JSON.parse(write(Opaque.new))

    assert_equal ["#<Opaque>", "JsonLinesContextWriterTest::Opaque"], [data["record"], data["record_class"]]
    assert_equal Time.at(0).utc.inspect, data["marks"].first["value"]
  end

  def test_writes_messages_with_invalid_utf8
    @ctx.failure = Metacrunch::Failure.new(error: JSON::ParserError.new("unexpected character: '\xFF'"),
                                           step: "source")

    assert_match(/unexpected character/, JSON.parse(write("x"))["failure"]["message"])
  end

  private

  def write(record)
    io = StringIO.new
    writer = Metacrunch::JsonLines::ContextWriter.new(io)
    writer.open(nil)
    writer.write(record, @ctx)
    writer.close
    io.string
  end

end
