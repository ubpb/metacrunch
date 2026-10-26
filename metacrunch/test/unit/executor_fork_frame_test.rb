# frozen_string_literal: true

require "test_helper"

class ExecutorForkFrameTest < Minitest::Test

  Frame = Metacrunch::Executor::Fork::Frame

  # Claims the size of a frame without holding its bytes.
  HugeData = Struct.new(:bytesize)

  def test_frames_pass_a_pipe_with_their_bytes_and_encodings
    records = ["Müller", "\xFF\xFE".b]
    reader, writer = IO.pipe
    Frame.write(writer, Marshal.dump(records))
    writer.close
    loaded = Frame.read(reader)

    assert_equal records, loaded
    assert_equal [Encoding::UTF_8, Encoding::BINARY], loaded.map(&:encoding)
    assert_nil Frame.read(reader)
  ensure
    reader.close
  end

  def test_a_frame_of_4_gib_or_more_is_refused
    io = StringIO.new
    error = assert_raises(Metacrunch::Error) { Frame.write(io, HugeData.new(2**32)) }

    assert_match(/\Aa batch of 4294967296 bytes is too large to send between processes/, error.message)
    assert_empty io.string
  end

  def test_a_frame_that_ends_early_is_truncated
    data = Marshal.dump("record")

    assert_raises(Frame::Truncated) { Frame.read(StringIO.new([data.bytesize].pack("N") + data[0, 2])) }
    assert_raises(Frame::Truncated) { Frame.read(StringIO.new("\x00\x00".b)) }
  end

end
