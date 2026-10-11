# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class JsonLinesWriterTest < Minitest::Test

  Writer = Metacrunch::JsonLines::Writer

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  # A pipe that breaks when the buffered data is flushed at the end.
  class PipeClosedBeforeFlush < StringIO

    def flush = raise(Errno::EPIPE)

  end

  def setup
    @dir = Dir.mktmpdir
    @ctx = Metacrunch::Context.new(id: 7, position: 3, logger: Logger.new(nil))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_writes_one_json_value_per_line
    io = StringIO.new
    writer = open_writer(io)
    writer.write({"a" => 1}, @ctx)
    writer.write_batch([2, "x"], [@ctx, @ctx])
    writer.close

    assert_equal "{\"a\":1}\n2\n\"x\"\n", io.string
    refute_predicate io, :closed?
  end

  def test_refuses_values_that_are_not_json
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write({"at" => Time.at(0)}, @ctx) }

    assert_equal "record at position 3 is not JSON (Hash): Time not allowed in JSON", error.message
  end

  def test_writes_files_and_gzip_files
    plain = File.join(@dir, "out.jsonl")
    gzip = File.join(@dir, "out.jsonl.gz")
    [plain, gzip].each do |path|
      writer = open_writer(path)
      writer.write({"a" => 1}, @ctx)
      writer.close
    end

    assert_equal "{\"a\":1}\n", File.read(plain)
    assert_equal "{\"a\":1}\n", Zlib::GzipReader.open(gzip, &:read)
  end

  def test_dash_writes_stdout
    stdout, = capture_io do
      writer = open_writer("-")
      writer.write(1, @ctx)
      writer.close
    end

    assert_equal "1\n", stdout
  end

  def test_a_closed_pipe_raises_sigpipe_once
    writer = open_writer(ClosedPipe.new)
    error = assert_raises(SignalException) { writer.write(1, @ctx) }
    writer.write(2, @ctx)
    writer.close

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_a_pipe_closed_before_the_final_flush_raises_sigpipe
    writer = open_writer(PipeClosedBeforeFlush.new)
    writer.write(1, @ctx)

    assert_raises(SignalException) { writer.close }
  end

  private

  def open_writer(target)
    writer = Writer.new(target)
    writer.open(nil)
    writer
  end

end
