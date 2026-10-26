# frozen_string_literal: true

require "test_helper"

class ValuesTest < Minitest::Test

  Marc = Metacrunch::Marc
  Values = Metacrunch::Marc::Values

  def test_characters_xml_cannot_represent
    assert_nil Values.unrepresentable("Tab\tand\nlines\r, Müller")
    assert_equal "\x1F", Values.unrepresentable("a\x1Fb")
    assert_equal "\uFFFE", Values.unrepresentable("a\uFFFEb")
  end

  def test_the_problem_of_a_value
    assert_nil Values.problem("Müller")
    assert_equal "invalid UTF-8", Values.problem("M\xFCller".dup.force_encoding(Encoding::UTF_8))
    assert_equal %("\\u001D" cannot be represented in XML 1.0), Values.problem("a\x1Db")
  end

  def test_parsed_checks_values
    error = assert_raises(Marc::ParseError) { Values.parsed("a\u0001", nil) { "field 245 $a" } }

    assert_equal %(field 245 $a: "\\u0001" cannot be represented in XML 1.0), error.message
  end

  def test_parsed_normalizes_with_nfc
    assert_equal "Mu\u0308ller", Values.parsed("Mu\u0308ller", nil) { "leader" }
    assert_equal "Müller", Values.parsed("Mu\u0308ller", :nfc) { "leader" }
  end

  def test_parsed_takes_other_encodings_as_the_serializers_do
    assert_equal "Müller", Values.parsed("Müller".encode("ISO-8859-1"), nil) { "leader" }
    assert_equal "Müller", Values.parsed("Müller".b, nil) { "leader" }
  end

  def test_serializable_values
    assert_equal "", Values.serializable(nil) { "leader" }
    assert_equal "12", Values.serializable(12) { "leader" }
    assert_equal Encoding::UTF_8, Values.serializable("Müller".encode("ISO-8859-1")) { "leader" }.encoding
  end

  def test_serializable_refuses_invalid_utf8
    error = assert_raises(Marc::SerializeError) { Values.serializable("x\xFF".b) { "field 001" } }

    assert_equal %(field 001: invalid UTF-8 "x\\xFF"), error.message
  end

  def test_the_place_is_asked_for_only_on_errors
    assert_equal "ok", Values.serializable("ok") { raise "the block ran" }
    assert_equal "ok", Values.parsed("ok", nil) { raise "the block ran" }
  end

  # So no terminal escape sequence of the data reaches a log.
  def test_locations_escape_invalid_bytes_and_control_characters
    assert_equal "field 245 $a", Values.location("245", "a")
    assert_equal "field 24\\xFF", Values.location("24\xFF".b)
    assert_equal "field 0\\x1B[31m1 $\\x01", Values.location("0\e[31m1", "\x01")
  end

end
