# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class OutputTest < Minitest::Test

  Output = Metacrunch::Output

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  # A pipe that breaks when the buffered data is flushed at the end.
  class PipeClosedBeforeFlush < StringIO

    def flush = raise(Errno::EPIPE)

  end

  # A disk without space.
  class FullDisk < StringIO

    def write(*) = raise(Errno::ENOSPC)

  end

  # Counts flushes.
  class Flushes < StringIO

    attr_reader :flushes

    def flush
      @flushes = (@flushes || 0) + 1
      super
    end

  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.chmod_R(0o755, @dir)
    FileUtils.remove_entry(@dir)
  end

  def test_writes_files_and_pathnames
    path = File.join(@dir, "out.jsonl")
    write_all(path, "a\n", "b\n")
    write_all(Pathname(File.join(@dir, "other.jsonl")), "c\n")

    assert_equal "a\nb\n", File.read(path)
    assert_equal "c\n", File.read(File.join(@dir, "other.jsonl"))
  end

  def test_gz_names_are_compressed_in_any_case
    ["out.jsonl.gz", "OUT.JSONL.GZ"].each do |name|
      path = File.join(@dir, name)
      write_all(path, "a\n")

      assert_equal "a\n", Zlib.gunzip(File.binread(path))
    end
  end

  def test_flush_writes_what_is_buffered_to_the_file
    path = File.join(@dir, "out.jsonl")
    output = Metacrunch::Output.new(path).open
    output.write("a\n")
    output.flush

    assert_equal "a\n", File.read(path)
  ensure
    output&.close
  end

  def test_flush_of_a_gzip_file_gives_whole_lines_so_far
    path = File.join(@dir, "out.jsonl.gz")
    output = Metacrunch::Output.new(path).open
    output.write("a\n")
    output.flush

    assert_equal "a\n", Zlib::Inflate.new(Zlib::MAX_WBITS + 32).inflate(File.binread(path))
  ensure
    output&.close
  end

  def test_flush_flushes_an_io_from_outside_and_does_nothing_before_open
    io = StringIO.new
    output = Metacrunch::Output.new(io)

    assert_nil output.flush
    output.open
    output.write("a")

    assert_nil output.flush
  end

  def test_overwrites_existing_files
    path = File.join(@dir, "out.jsonl")
    File.write(path, "old content\n")
    write_all(path, "new\n")

    assert_equal "new\n", File.read(path)
  end

  def test_names_it_cannot_write_are_refused_before_anything_is_created
    {"out.jsonl.zst" => "metacrunch cannot write zstd; write plain output and compress it, " \
                        "e.g. metacrunch run job.rb | zstd > PATH",
     "out.jsonl.bz2" => "metacrunch cannot write bzip2; write plain output and compress it, " \
                        "e.g. metacrunch run job.rb | bzip2 > PATH",
     "out.jsonl.xz" => "metacrunch cannot write xz; write plain output and compress it, " \
                       "e.g. metacrunch run job.rb | xz > PATH",
     "out.zip" => "metacrunch cannot write zip; write plain output and compress it, " \
                  "e.g. metacrunch run job.rb | zip -q PATH -",
     "out.tar" => "metacrunch cannot write tar archives", "out.tar.gz" => "metacrunch cannot write tar archives",
     "out.tgz" => "metacrunch cannot write tar archives", "OUT.TGZ" => "metacrunch cannot write tar archives"}
      .each do |name, text|
      path = File.join(@dir, name)
      error = assert_raises(Metacrunch::OutputError) { Output.new(path).open }

      assert_equal "#{path}: #{text.sub("PATH", path)}", error.message
      refute_path_exists path
    end
  end

  def test_the_hint_for_a_refused_name_quotes_the_path
    path = File.join(@dir, "my out.jsonl.zst")
    error = assert_raises(Metacrunch::OutputError) { Output.new(path).open }

    assert error.message.end_with?("| zstd > #{path.gsub(" ", "\\ ")}")
  end

  def test_dash_is_the_stdout_of_open
    stdout, = capture_io { write_all("-", "a\n") }

    assert_equal "a\n", stdout
  end

  def test_ios_from_outside_are_flushed_not_closed
    io = Flushes.new
    write_all(io, "a\n")

    assert_equal ["a\n", 1], [io.string, io.flushes]
    refute_predicate io, :closed?
  end

  def test_a_closed_pipe_raises_sigpipe_once
    output = Output.new(ClosedPipe.new).open
    error = assert_raises(SignalException) { output.write("a\n") }
    output.write("b\n")
    output.close

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_a_pipe_closed_before_the_final_flush_raises_sigpipe
    output = Output.new(PipeClosedBeforeFlush.new).open
    output.write("a\n")

    assert_raises(SignalException) { output.close }
  end

  # The reader takes one byte and goes away; the writer runs into EPIPE.
  def test_a_closed_pipe_of_an_own_fifo_closes_it
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    reader = Thread.new { File.open(fifo) { it.read(1) } }
    output = Output.new(fifo).open

    assert_raises(SignalException) { 100.times { output.write("x" * 65_536) } }
    reader.join
    output.close

    assert(ObjectSpace.each_object(File).none? { it.path == fifo && !it.closed? })
  end

  def test_close_returns_nil_also_for_ios_from_outside
    output = Output.new(StringIO.new).open
    output.write("a\n")

    assert_nil output.close
  end

  # The disk fills up while the gzip trailer is written; the file then fails
  # to close as well. The run sees one OutputError, not a bare Errno.
  def test_a_full_disk_while_closing_an_own_gzip_file
    path = File.join(@dir, "out.jsonl.gz")
    output = Output.new(path).open
    file = output.instance_variable_get(:@file)
    file.define_singleton_method(:write) { |*| raise Errno::ENOSPC }
    file.define_singleton_method(:close) { raise Errno::ENOSPC }
    error = assert_raises(Metacrunch::OutputError) { output.close }

    assert_equal "#{path}: no space left on device", error.message
  ensure
    IO.instance_method(:close).bind_call(file) if file && !file.closed?
  end

  def test_close_before_open_and_twice_does_nothing
    output = Output.new(StringIO.new).open
    output.close

    assert_nil Output.new(StringIO.new).close
    assert_nil output.close
  end

  def test_write_before_open
    error = assert_raises(IOError) { Output.new(StringIO.new).write("a") }

    assert_equal "StringIO: not open", error.message
  end

  def test_open_twice
    output = Output.new(StringIO.new).open
    error = assert_raises(Metacrunch::OutputError) { output.open }

    assert_equal "StringIO: already open", error.message
  end

  def test_errors_on_open
    missing = File.join(@dir, "missing", "out.jsonl")

    assert_equal "#{missing}: no such directory", open_error(missing)
    assert_equal "#{@dir}: is a directory", open_error(@dir)
  end

  def test_no_permission
    skip "root writes everywhere" if Process.uid.zero?
    locked = File.join(@dir, "locked")
    FileUtils.mkdir(locked)
    File.chmod(0o500, locked)
    path = File.join(locked, "out.jsonl")

    assert_equal "#{path}: permission denied", open_error(path)
  end

  def test_errors_while_writing
    output = Output.new(FullDisk.new).open
    error = assert_raises(Metacrunch::OutputError) { output.write("a") }

    assert_equal "OutputTest::FullDisk: no space left on device", error.message
    assert_instance_of Errno::ENOSPC, error.cause
  end

  def test_invalid_targets
    [42, nil, ""].each do |target|
      error = assert_raises(ArgumentError) { Output.new(target) }

      assert_match(/\Aa target must be a path, "-" or an IO, got /, error.message)
    end
  end

  def test_new_creates_nothing
    Output.new(File.join(@dir, "out.jsonl"))

    assert_empty Dir.children(@dir)
  end

  private

  def write_all(target, *strings)
    output = Output.new(target).open
    strings.each { output.write(it) }
    output.close
  end

  def open_error(target) = assert_raises(Metacrunch::OutputError) { Output.new(target).open }.message

end
