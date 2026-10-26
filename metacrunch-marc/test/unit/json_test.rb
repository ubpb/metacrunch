# frozen_string_literal: true

require "test_helper"
require "json"

class JsonTest < Minitest::Test

  include Inputs

  Marc = Metacrunch::Marc
  Json = Metacrunch::Marc::Json
  LINE = %({"leader":"00000nam a2200000 c 4500","fields":[{"001":"1"},) +
         %({"245":{"ind1":"1","ind2":"0","subfields":[{"a":"Title"}]}}]})
  HINT = "(MARC-in-JSON has one record per line; jq -c . in.json > out.jsonl converts pretty-printed JSON)"

  def test_parses_a_line
    record = Json.parse(LINE)

    assert_equal "00000nam a2200000 c 4500", record.leader
    assert_equal ["=001  1", "=245  10$aTitle"], record.fields.map(&:to_s)
  end

  def test_parses_a_pretty_printed_object
    assert_equal Json.parse(LINE), Json.parse(JSON.pretty_generate(JSON.parse(LINE)))
  end

  def test_each_reads_one_record_per_line
    assert_equal [Json.parse(LINE)] * 2, Json.each("#{LINE}\n#{LINE}\n").to_a
  end

  def test_each_raw_yields_lines_without_their_break
    assert_equal [LINE, LINE], Json.each_raw("#{LINE}\n#{LINE}\n").to_a
    assert(Json.each_raw(LINE).all? { it.encoding == Encoding::UTF_8 })
  end

  def test_each_raw_skips_blank_lines_and_byte_order_marks
    assert_equal [LINE, LINE], Json.each_raw("\xEF\xBB\xBF#{LINE}\n\n  \n\xEF\xBB\xBF#{LINE}\n".b).to_a
  end

  def test_each_raw_takes_crlf_and_a_last_line_without_a_break
    assert_equal [LINE, LINE], Json.each_raw("#{LINE}\r\n#{LINE}").to_a
  end

  def test_reads_ios_in_chunks
    input = Array.new(500) { LINE }.join("\n")

    assert_equal 500, Json.each(Chunked.new(input, 1_000)).count
    assert_equal 500, Json.each_raw(ReadOnly.new(input)).count
  end

  def test_a_json_array
    error = assert_raises(Marc::ParseError) { Json.parse("[#{LINE}]") }

    assert_match(/\Aa record must be a JSON object, got \[\{"leader" => /, error.message)
  end

  def test_other_json_values
    assert_equal "a record must be a JSON object, got 12", assert_raises(Marc::ParseError) { Json.parse("12") }.message
  end

  def test_duplicate_keys
    error = assert_raises(Marc::ParseError) { Json.parse(%({"fields": [], "fields": []})) }

    assert_equal %(duplicate key "fields" at line 1 column 1), error.message
  end

  # Ruby's own json 2.x keeps the last of duplicate keys unless told not to.
  def test_duplicate_codes_inside_a_field
    error = assert_raises(Marc::ParseError) { Json.parse(%({"fields":[{"245":{"subfields":[{"a":"x","a":"y"}]}}]})) }

    assert_equal %(duplicate key "a" at line 1 column 33), error.message
  end

  def test_invalid_utf8
    error = assert_raises(Marc::ParseError) { Json.parse(%({"fields": [{"001": "\xFF"}]}).b) }

    assert_equal "invalid UTF-8", error.message
  end

  def test_a_blank_string
    assert_equal "no record found", assert_raises(Marc::ParseError) { Json.parse("  \n") }.message
  end

  def test_a_pretty_printed_line_gets_a_hint
    error = assert_raises(Marc::ParseError) { Json.parse("{") }

    assert_equal " #{HINT}", error.message[-(HINT.size + 1)..]
  end

  def test_a_broken_whole_object_gets_no_hint
    error = assert_raises(Marc::ParseError) { Json.parse(%({"fields": [}})) }

    refute_includes error.message, HINT
  end

  def test_normalize
    assert_equal "Müller", Json.parse(%({"fields": [{"001": "Mu\u0308ller"}]}), normalize: :nfc)["001"].value
  end

  def test_serializes_as_json_generate_of_to_h
    record = Json.parse(LINE)

    assert_equal "#{JSON.generate(record.to_h)}\n", Json::Serializer.record(record)
  end

  def test_serializing_keeps_to_the_common_rule
    record = Marc::Record.new(fields: [Marc::ControlField.new("001", "a\u0001")])
    error = assert_raises(Marc::SerializeError) { Json::Serializer.record(record) }

    assert_equal %(field 001: "\\u0001" cannot be represented in XML 1.0), error.message
  end

  def test_serializing_checks_indicators
    record = Marc::Record.new(fields: [Marc::DataField.new("245", " ", "\u0001", [["a", "x"]])])
    error = assert_raises(Marc::SerializeError) { Json::Serializer.record(record) }

    assert_equal %(field 245: "\\u0001" cannot be represented in XML 1.0), error.message
  end

  def test_serializing_transcodes_and_drops_the_type
    field = Marc::ControlField.new("001", "Müller".encode("ISO-8859-1"))
    record = Marc::Record.new(type: "Bibliographic", fields: [field])

    assert_equal %({"fields":[{"001":"Müller"}]}\n), Json::Serializer.record(record)
  end

  def test_rejects_invalid_arguments
    assert_raises(ArgumentError) { Json.parse(nil) }
    assert_raises(ArgumentError) { Json.each_raw(nil) }
    assert_raises(ArgumentError) { Json.each(LINE, normalize: :nfd) }
  end

end
