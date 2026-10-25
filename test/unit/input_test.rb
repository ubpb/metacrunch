# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class InputTest < Minitest::Test

  Input = Metacrunch::Input

  # An IO that can only read, as some wrappers do.
  class ReadOnly

    def initialize(content)
      @io = StringIO.new(content)
    end

    def read(length = nil) = @io.read(length)

  end

  # An IO that only has readpartial.
  class PartialOnly

    def initialize(content)
      @io = StringIO.new(content)
    end

    def readpartial(length) = @io.readpartial(length)

  end

  # A device that fails while reading.
  class Failing

    def readpartial(_length) = raise(Errno::EIO)

  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.chmod_R(0o755, @dir)
    FileUtils.remove_entry(@dir)
  end

  def test_reads_paths_pathnames_and_arrays_in_order
    first = write("a.jsonl", "1\n")
    second = write("b.jsonl", "2\n")

    assert_equal [[first, "1\n"], [second, "2\n"]], documents([first, Pathname(second)])
  end

  def test_dash_reads_stdin
    original = $stdin
    $stdin = StringIO.new("in\n")

    assert_equal [["-", "in\n"]], documents("-")
  ensure
    $stdin = original
  end

  def test_reads_ios_from_where_they_are_and_leaves_them_open
    io = StringIO.new("abc")
    io.read(1)
    input = Input.new(io)

    assert_equal [["StringIO", "bc"]], documents(input)
    assert_equal [["StringIO", ""]], documents(input)
    refute_predicate io, :closed?
  end

  def test_ios_with_only_read_or_only_readpartial
    assert_equal [["InputTest::ReadOnly", "r"]], documents(ReadOnly.new("r"))
    assert_equal [["InputTest::PartialOnly", "p"]], documents(PartialOnly.new("p"))
  end

  def test_files_given_as_ios_are_named_by_their_path
    path = write("a.jsonl", "1\n")

    File.open(path) { assert_equal [[path, "1\n"]], documents(it) }
  end

  def test_invalid_targets
    [42, nil, "", [["a.jsonl"]], [1]].each do |target|
      error = assert_raises(ArgumentError) { Input.new(target) }

      assert_match(/\Aa target must be a path, "-" or an IO, got /, error.message)
    end
  end

  def test_targets_must_not_be_empty
    assert_equal "targets must not be empty", assert_raises(ArgumentError) { Input.new([]) }.message
  end

  def test_new_touches_no_file_and_input_is_no_source
    input = Input.new(File.join(@dir, "missing.jsonl"))

    refute_respond_to input, :each
    assert_nil input.progress
  end

  def test_all_paths_are_checked_before_the_first_document
    missing = File.join(@dir, "missing.jsonl")
    seen = []
    error = assert_raises(Metacrunch::InputError) do
      Input.new([write("a.jsonl", "1"), write("b.jsonl", "2"), missing]).each_document { seen << it }
    end

    assert_empty seen
    assert_equal "#{missing}: no such file", error.message
  end

  def test_a_directory_is_no_target
    error = assert_raises(Metacrunch::InputError) { documents(@dir) }

    assert_equal "#{@dir}: is a directory", error.message
  end

  def test_an_unreadable_file
    skip "root reads every file" if Process.uid.zero?
    path = write("secret.jsonl", "1\n")
    File.chmod(0o000, path)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}: permission denied", error.message
  end

  def test_errors_while_reading_name_the_target
    error = assert_raises(Metacrunch::InputError) { documents(Failing.new) }

    assert_equal "InputTest::Failing: input/output error", error.message
    assert_instance_of Errno::EIO, error.cause
  end

  def test_a_fifo_in_an_array_is_read_without_progress
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    writer = Thread.new { File.write(fifo, "from the fifo\n") }
    input = Input.new([fifo, write("a.jsonl", "1\n")])

    assert_equal ["from the fifo\n", "1\n"], documents(input).map(&:last)
    assert_nil input.progress
  ensure
    writer&.join
  end

  def test_progress_from_before_to_after_reading
    input = Input.new([write("big.jsonl", "x" * (3 * Metacrunch::Input::Stream::BLOCK)), write("small.jsonl", "y")])
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert_in_delta 1.0, input.progress
    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
  end

  def test_progress_starts_again_with_every_call
    path = write("big.jsonl", "x" * (3 * Metacrunch::Input::Stream::BLOCK))
    input = Input.new(path)
    documents(input)
    first = nil
    input.each_document { |stream, _name| first ||= stream.read(1) && input.progress }

    assert_operator first, :<, 1.0
  end

  def test_progress_of_empty_files_and_without_a_total
    empty = Input.new(write("empty.jsonl", ""))
    documents(empty)
    with_stdin = Input.new([write("a.jsonl", "1"), StringIO.new("2")])
    documents(with_stdin)

    assert_in_delta 1.0, empty.progress
    assert_nil with_stdin.progress
  end

  def test_progress_can_be_read_from_another_thread
    input = Input.new(write("big.jsonl", "x\n" * 200_000))
    values = Queue.new
    reader = Thread.new { 200.times { values << input.progress } }
    input.each_document { |stream, _name| stream.each_line { nil } }
    reader.join
    seen = Array.new(values.size) { values.pop }.compact

    assert_equal seen, seen.sort
  end

  def test_files_are_closed_on_break_errors_and_throw
    path = write("a.jsonl", "1\n2\n")
    Input.new(path).each_document { break }

    assert_raises(RuntimeError) { Input.new(path).each_document { raise "stop" } }
    catch(:done) { Input.new(path).each_document { throw :done } }

    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  def test_a_stream_is_closed_after_its_document
    kept = nil
    Input.new(StringIO.new("abc")).each_document { |stream, _name| kept = stream }

    assert_raises(IOError) { kept.read }
  end

  def test_each_document_without_a_block_is_an_enumerator
    path = write("a.jsonl", "1\n")

    assert_equal([[path, "1\n"]], Input.new(path).each_document.map { |stream, name| [name, stream.read] })
  end

  private

  def documents(input)
    input = Input.new(input) unless input.is_a?(Input)
    result = []
    input.each_document { |stream, name| result << [name, stream.read] }
    result
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
