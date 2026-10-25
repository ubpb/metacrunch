# frozen_string_literal: true

require "test_helper"
require "metacrunch/input/stream"

class InputStreamTest < Minitest::Test

  Stream = Metacrunch::Input::Stream

  # A source that hands out the given blocks one per readpartial and
  # records the lengths asked for.
  class Blocks

    attr_reader :lengths

    def initialize(*blocks)
      @blocks = blocks
      @lengths = []
    end

    def readpartial(length)
      @lengths << length
      @blocks.shift || raise(EOFError, "end")
    end

  end

  def stream(*blocks) = Stream.new(Blocks.new(*blocks.map(&:b)))

  def test_read_without_length_reads_the_rest
    stream = stream("ab", "cd")

    assert_equal "abcd", stream.read
    assert_equal "", stream.read
  end

  def test_read_of_nothing
    assert_equal "", stream("a").read(0)
  end

  def test_read_with_length_reads_up_to_it_and_nil_at_the_end
    stream = stream("abc", "de")

    assert_equal "abcd", stream.read(4)
    assert_equal "e", stream.read(4)
    assert_nil stream.read(1)
  end

  def test_readpartial_reads_up_to_length_and_raises_at_the_end
    stream = stream("abc")

    assert_equal "ab", stream.readpartial(2)
    assert_equal "c", stream.readpartial(10)
    assert_raises(EOFError) { stream.readpartial(1) }
  end

  def test_readpartial_replaces_the_content_of_outbuf
    buffer = +"old"

    assert_same buffer, stream("abc").readpartial(10, buffer)
    assert_equal "abc", buffer
  end

  def test_peek_does_not_consume
    stream = stream("ab", "cd")

    assert_equal "abc", stream.peek(3)
    assert_equal "abcd", stream.peek(10)
    assert_equal "abcd", stream.read
  end

  def test_peek_at_the_end
    assert_equal "", stream.peek(1)
  end

  def test_eof
    stream = stream("a")

    refute_predicate stream, :eof?
    stream.read(1)

    assert_predicate stream, :eof?
  end

  def test_each_line_keeps_line_ends_and_the_last_line_without_one
    lines = stream("a\r\nb\n", "\n", "\nlast").each_line.to_a

    assert_equal ["a\r\n", "b\n", "\n", "\n", "last"], lines
  end

  def test_lines_span_blocks_and_may_be_longer_than_a_block
    long = "x" * (Stream::BLOCK + 10)
    lines = stream("1\n2", "3\n#{long[0, 100]}", long[100..], "\n4").each_line.to_a

    assert_equal ["1\n", "23\n", "#{long}\n", "4"], lines
  end

  def test_each_line_without_a_block_is_an_enumerator
    assert_instance_of Enumerator, stream("a\n").each_line
  end

  def test_an_empty_source_has_no_lines
    assert_empty stream.each_line.to_a
    assert_predicate stream, :eof?
  end

  def test_frozen_and_utf8_blocks_from_the_source
    source = Blocks.new("ä\n", "ö\n".encode(Encoding::UTF_8).freeze)
    lines = Stream.new(source).each_line.to_a

    assert_equal ["ä\n".b, "ö\n".b], lines
    assert(lines.all? { it.encoding == Encoding::BINARY && !it.frozen? })
  end

  def test_reads_the_source_in_blocks
    source = Blocks.new("a")
    Stream.new(source).read

    assert_equal [Stream::BLOCK, Stream::BLOCK], source.lengths
  end

  def test_unread_puts_bytes_in_front
    stream = stream("cd")
    stream.unread("ab")

    assert_equal "abcd", stream.read
  end

  def test_a_closed_stream_raises
    stream = stream("a")
    stream.close

    [-> { stream.read }, -> { stream.readpartial(1) }, -> { stream.each_line { nil } }, -> { stream.peek(1) },
     -> { stream.eof? }].each do |call|
      assert_equal "stream closed", assert_raises(IOError, &call).message
    end
  end

end
