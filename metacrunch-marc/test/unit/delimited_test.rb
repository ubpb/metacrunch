# frozen_string_literal: true

require "test_helper"

class DelimitedTest < Minitest::Test

  include Inputs

  Delimited = Metacrunch::Marc::Delimited

  # Hands out UTF-8 Strings, as an IO with an external encoding may.
  class Utf8Chunks

    def initialize(chunks)
      @chunks = chunks.dup
    end

    def read(_length) = @chunks.shift

  end

  def test_cuts_after_each_delimiter_and_keeps_the_rest
    assert_equal ["a|", "bc|", "d"], pieces("a|bc|d")
    assert_equal ["a|", "|"], pieces("a||")
    assert_empty pieces("")
  end

  def test_pieces_are_binary
    assert(pieces("ä|ö").all? { it.encoding == Encoding::BINARY })
  end

  def test_reads_ios_in_chunks_of_any_size
    text = Array.new(5_000) { "record #{it}|" }.join
    expected = pieces(text)

    [1, 7, 65_536, 100_003].each { assert_equal expected, pieces(Chunked.new(text, it)), "chunks of #{it}" }

    assert_equal expected, pieces(ReadOnly.new(text))
    assert_equal expected.first(50), pieces(Trickle.new(expected.first(50).join))
  end

  def test_a_piece_over_many_chunks
    long = "x" * 300_000

    assert_equal ["#{long}|", "y"], pieces(Chunked.new("#{long}|y", 4_096))
  end

  def test_drops_taken_pieces_of_a_long_input
    text = Array.new(30_000) { "record #{it}|" }.join

    assert_equal pieces(text), pieces(Chunked.new(text, 4_096))
  end

  def test_reads_chunks_in_other_encodings
    assert_equal ["ä|".b, "ö|".b, "ü".b], pieces(Utf8Chunks.new(["ä|", "ö|ü"]))
  end

  private

  def pieces(input) = Delimited.new(input, "|".b).enum_for(:each).to_a

end
