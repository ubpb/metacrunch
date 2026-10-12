# frozen_string_literal: true

require "test_helper"

class MarcxmlTest < Minitest::Test

  def test_version
    assert_equal "5.0.0.pre", Metacrunch::Marcxml::VERSION
  end

  def test_namespace
    assert_equal "http://www.loc.gov/MARC21/slim", Metacrunch::Marcxml::NAMESPACE
  end

  def test_parse_error_names_the_position
    error = Metacrunch::Marcxml::ParseError.new("bad", line: 3, column: 7)

    assert_equal "bad (line 3, column 7)", error.message
    assert_equal [3, 7], [error.line, error.column]
  end

  def test_parse_error_without_a_position
    error = Metacrunch::Marcxml::ParseError.new("bad")

    assert_equal "bad", error.message
    assert_nil error.line
  end

  def test_errors_share_a_base_class
    assert_operator Metacrunch::Marcxml::ParseError, :<, Metacrunch::Marcxml::Error
    assert_operator Metacrunch::Marcxml::SerializeError, :<, Metacrunch::Marcxml::Error
  end

end
