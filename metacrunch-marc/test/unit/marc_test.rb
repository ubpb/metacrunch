# frozen_string_literal: true

require "test_helper"
require "json"

class MarcTest < Minitest::Test

  include Iso

  def test_version
    assert_equal "1.0.0.pre", Metacrunch::Marc::VERSION
  end

  def test_namespace
    assert_equal "http://www.loc.gov/MARC21/slim", Metacrunch::Marc::Xml::NAMESPACE
  end

  def test_parse_error_names_the_position
    error = Metacrunch::Marc::ParseError.new("bad", line: 3, column: 7)

    assert_equal "bad (line 3, column 7)", error.message
    assert_equal [3, 7], [error.line, error.column]
  end

  def test_parse_error_without_a_position
    error = Metacrunch::Marc::ParseError.new("bad")

    assert_equal "bad", error.message
    assert_nil error.line
  end

  def test_errors_share_a_base_class
    assert_operator Metacrunch::Marc::ParseError, :<, Metacrunch::Marc::Error
    assert_operator Metacrunch::Marc::SerializeError, :<, Metacrunch::Marc::Error
  end

  def test_parse_detects_the_format
    record = Metacrunch::Marc::Xml.parse(%(<record><controlfield tag="001">1</controlfield></record>))

    [record.to_xml, record.to_iso2709, JSON.generate(record.to_h)].each do |string|
      assert_equal record.fields, Metacrunch::Marc.parse(string).fields
    end
  end

  def test_parse_skips_a_byte_order_mark_and_whitespace
    assert_equal ["1"], Metacrunch::Marc.parse(%(\uFEFF\n  {"fields": [{"001": "1"}]})).values("001")
    assert_equal ["1"], Metacrunch::Marc.parse("\xEF\xBB\xBF\n#{book}".b).values("001")
  end

  def test_parse_normalizes
    assert_equal "Müller", Metacrunch::Marc.parse(raw(["001", "Mu\u0308ller"]), normalize: :nfc)["001"].value
  end

  def test_parse_errors
    {
      " \n" => "no record found",
      "id;title\n1;x\n" => %(neither MARCXML, ISO 2709 nor MARC-in-JSON: it starts with "id;title\\n1;x\\n"),
      %([{"fields": []}]) => %(a record must be a JSON object, got [{"fields" => []}])
    }.each do |string, message|
      error = assert_raises(Metacrunch::Marc::ParseError) { Metacrunch::Marc.parse(string) }

      assert_equal message, error.message
    end
  end

  def test_parse_rejects_invalid_arguments
    assert_raises(ArgumentError) { Metacrunch::Marc.parse(nil) }
    assert_raises(ArgumentError) { Metacrunch::Marc.parse(" ", normalize: :nfd) }
  end

end
