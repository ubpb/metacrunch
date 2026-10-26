# frozen_string_literal: true

require "test_helper"

class MarcTest < Minitest::Test

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

end
