# frozen_string_literal: true

require "test_helper"

class TextTest < Minitest::Test

  def test_crlf_and_invalid_bytes
    assert_equal({text: "a\nb�", title: nil, lang: nil}, extract("a\r\nb\xFF".b))
  end

  def test_a_bom_is_dropped
    assert_equal "# Rules", extract("\xEF\xBB\xBF# Rules".b)[:text]
  end

  def test_a_string_in_another_encoding
    assert_equal "Öffnungszeiten", extract("Öffnungszeiten".encode(Encoding::ISO_8859_1))[:text]
  end

  def test_nil_is_empty
    assert_equal "", extract(nil)[:text]
  end

  def test_types
    assert_equal ["text/plain", "text/markdown"], Metacrunch::Ai::Text.new.types
  end

  private

  def extract(content) = Metacrunch::Ai::Text.new.extract(content, type: "text/markdown")

end
