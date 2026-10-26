# frozen_string_literal: true

require "test_helper"

class LinesTest < Minitest::Test

  def test_gets_reads_up_to_the_limit_in_the_encoding
    block = lines("abc", Encoding::BINARY) { it.gets(nil, 2) }

    assert_equal "ab".b, block
    assert_equal Encoding::BINARY, block.encoding
  end

  def test_gets_returns_nil_at_the_end
    assert_nil(lines("", Encoding::UTF_8) { it.gets(nil, 10) })
  end

  def test_gets_without_a_limit_reads_a_block
    assert_equal "a" * Metacrunch::Csv::Lines::BLOCK, lines("a" * 70_000, Encoding::UTF_8, &:gets)
  end

  def test_a_character_split_by_the_limit_is_completed
    emoji = "😀".encode(Encoding::UTF_16LE)
    block = lines(emoji, Encoding::UTF_16LE) { it.gets(nil, 2) }

    assert_equal emoji, block
  end

  def test_invalid_bytes_stay_invalid
    block = lines("\x00\xD8a\x00b\x00c\x00".b, Encoding::UTF_16LE) { it.gets(nil, 2) }

    refute_predicate block, :valid_encoding?
    assert_equal 5, block.bytesize
  end

  def test_the_encodings_csv_asks_for
    encodings = lines("", Encoding::UTF_16LE) { [it.external_encoding, it.internal_encoding] }

    assert_equal [Encoding::UTF_16LE, nil], encodings
  end

  def test_eof_asks_the_stream
    assert(lines("a", Encoding::UTF_8) { [it.eof?, it.gets(nil, 1), it.eof?] == [false, "a", true] })
  end

  private

  # Yields Lines over bytes and returns what the block returns.
  def lines(bytes, encoding)
    Metacrunch::Input.new(StringIO.new(bytes.b)).each_document do |stream, _name|
      return yield Metacrunch::Csv::Lines.new(stream, encoding)
    end
  end

end
