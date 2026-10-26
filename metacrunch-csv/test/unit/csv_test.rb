# frozen_string_literal: true

require "test_helper"

class CsvTest < Minitest::Test

  Csv = Metacrunch::Csv

  def test_encoding_finds_the_encoding
    assert_equal Encoding::Windows_1252, Csv.encoding(";", '"', "Windows-1252")
  end

  def test_an_unknown_encoding_is_an_argument_error
    error = assert_raises(ArgumentError) { Csv.encoding(",", '"', "Klingon") }

    assert_equal 'encoding must be the name of an encoding, got "Klingon"', error.message
  end

  def test_an_encoding_without_byte_order_is_an_argument_error
    error = assert_raises(ArgumentError) { Csv.encoding(",", '"', "UTF-16") }

    assert_equal "encoding UTF-16 has no byte order; use UTF-16LE, UTF-16BE or another encoding", error.message
  end

  def test_other_dummy_encodings_are_argument_errors
    error = assert_raises(ArgumentError) { Csv.encoding(",", '"', "ISO-2022-JP") }

    assert_equal "encoding ISO-2022-JP cannot be read or written: Ruby knows only its name", error.message
  end

  def test_col_sep_is_a_non_empty_string
    [nil, "", 1].each do |col_sep|
      assert_raises(ArgumentError) { Csv.encoding(col_sep, '"', "UTF-8") }
    end
  end

  def test_quote_char_is_one_character_other_than_col_sep
    [nil, "", "''", ","].each do |quote_char|
      assert_raises(ArgumentError) { Csv.encoding(",", quote_char, "UTF-8") }
    end
  end

  def test_separators_must_exist_in_the_encoding
    error = assert_raises(ArgumentError) { Csv.encoding("€", '"', "ISO-8859-1") }

    assert_equal '"€" cannot be written in ISO-8859-1', error.message
  end

  def test_utf8_and_single_byte_encodings_are_bytewise
    assert(["UTF-8", "ISO-8859-1", "Windows-1252", "IBM437"].all? { Csv.bytewise?(Encoding.find(it)) })
  end

  def test_other_encodings_are_not_bytewise
    assert(["UTF-16LE", "UTF-16BE", "Shift_JIS", "GB18030"].none? { Csv.bytewise?(Encoding.find(it)) })
  end

end
