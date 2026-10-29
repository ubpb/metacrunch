# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tempfile"
require "tmpdir"

class InputZipTest < Minitest::Test

  include Override

  Input = Metacrunch::Input

  def setup
    @dir = Dir.mktmpdir
    @tmp = File.join(@dir, "tmp")
    Dir.mkdir(@tmp)
    @tmpdir = ENV.fetch("TMPDIR", nil)
    ENV["TMPDIR"] = @tmp
  end

  def teardown
    ENV["TMPDIR"] = @tmpdir
    FileUtils.remove_entry(@dir)
  end

  def test_every_document_entry_is_a_document
    archive = zip("data/a.csv" => "1\n", "readme.txt" => "r", "d/" => :directory, "link" => :symlink,
                  "d/.DS_Store" => "x", "__MACOSX/._a.csv" => "x")

    ["export.zip", "export.dat"].each do |name|
      path = write(name, archive)

      assert_equal [["#{path}:data/a.csv", "1\n"], ["#{path}:readme.txt", "r"]], documents(path)
    end
  end

  def test_repeated_names_are_documents_each
    path = write("twice.zip", ZipBuilder.build([{name: "a.csv", data: "1"}, {name: "a.csv", data: "2"}]))

    assert_equal [["#{path}:a.csv", "1"], ["#{path}:a.csv", "2"]], documents(path)
  end

  def test_documents_are_detected_again
    inner_tar = tar("c.jsonl" => "3\n")
    path = write("outer.zip", zip("a.jsonl.gz" => Zlib.gzip("1\n"), "inner.tar" => inner_tar,
                                  "inner.zip" => zip("d.jsonl" => "4\n")))

    assert_equal [["#{path}:a.jsonl.gz", "1\n"], ["#{path}:inner.tar:c.jsonl", "3\n"],
                  ["#{path}:inner.zip:d.jsonl", "4\n"]], documents(path)
  end

  def test_zip_inside_tar_gz
    path = write("dump.tar.gz", Zlib.gzip(tar("part.zip" => zip("a.csv" => "1\n"))))

    assert_equal [["#{path}:part.zip:a.csv", "1\n"]], documents(path)
  end

  def test_zip_counts_as_a_layer
    archive = 5.times.reduce("x") { |data, level| zip("#{level}.zip" => data) }
    path = write("deep.zip", archive)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_match(/: more than 4 layers of gzip, tar and zip\z/, error.message)
  end

  def test_empty_archive_gives_no_document
    assert_empty documents(write("empty.zip", zip({})))
  end

  def test_stdin_and_pipes_go_through_a_temporary_file
    archive = zip("a.csv" => "1\n")
    seen = []
    original = $stdin
    $stdin = piped(archive)
    stdin = []
    Input.new("-").each_document { |stream, name| stdin << [name, stream.read, temporary_files] }
    Input.new(piped(archive)).each_document { |stream, _name| seen << [stream.read, temporary_files] }

    assert_equal [["-:a.csv", "1\n", 1]], stdin
    assert_equal [["1\n", 1]], seen
    assert_equal 0, temporary_files
  ensure
    $stdin = original
  end

  def test_a_stringio_is_read_directly_from_its_position
    io = StringIO.new("junk#{zip("a.csv" => "1\n")}")
    io.read(4)

    without_temporary_files { assert_equal [["StringIO:a.csv", "1\n"]], documents(io) }
  end

  def test_a_path_is_read_directly
    path = write("a.zip", zip("a.csv" => "1\n"))

    without_temporary_files { assert_equal [["#{path}:a.csv", "1\n"]], documents(path) }
  end

  def test_a_fifo_path_goes_through_a_temporary_file
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    writer = Thread.new { File.binwrite(fifo, zip("a.csv" => "1\n")) }

    assert_equal [["#{fifo}:a.csv", "1\n"]], documents(fifo)
  ensure
    writer&.join
  end

  # A File can seek, but not on a FIFO: pos raises.
  def test_a_fifo_given_as_an_io_goes_through_a_temporary_file
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    writer = Thread.new { File.binwrite(fifo, zip("a.csv" => "1\n")) }
    names = File.open(fifo, "rb") { |io| documents(io).map(&:first) }

    assert_equal ["#{fifo}:a.csv"], names
  ensure
    writer&.join
  end

  def test_documents_read_only_in_part_are_still_checked
    path = write("parts.zip", zip("a.txt" => "a" * 3000, "b.txt" => "b" * 3000))
    heads = []
    Input.new(path).each_document { |stream, _name| heads << stream.read(2) }

    assert_equal ["aa", "bb"], heads

    broken = write("broken.zip", ZipBuilder.build([{name: "a.txt", data: "a" * 3000, crc: 1}]))
    error = assert_raises(Metacrunch::InputError) { Input.new(broken).each_document { |stream, _| stream.read(2) } }

    assert_equal "#{broken}:a.txt: broken zip archive (wrong CRC32)", error.message
  end

  def test_breaking_out_removes_the_temporary_file
    Input.new(piped(zip("a.csv" => "1\n", "b.csv" => "2\n"))).each_document { break }

    assert_equal 0, temporary_files
  end

  def test_an_interrupt_removes_the_temporary_file
    queue = Queue.new
    reading = Queue.new
    thread = Thread.new do
      Input.new(piped(zip("a.csv" => "1\n"))).each_document do
        reading << true
        queue.pop
      end
    end
    thread.report_on_exception = false
    reading.pop(timeout: 5)
    thread.raise(Interrupt)

    assert_raises(Interrupt) { thread.join }
    assert_equal 0, temporary_files
  end

  def test_an_error_while_copying_names_the_target
    original = $stdin
    $stdin = piped(zip("a.csv" => "1\n"))
    error = override(IO, :copy_stream, ->(*) { raise Errno::ENOSPC }) do
      assert_raises(Metacrunch::InputError) { documents("-") }
    end

    assert_equal "-: no space left on device", error.message
  ensure
    $stdin = original
  end

  def test_progress_of_a_zip_path
    input = Input.new(write("random.zip", zip("a.bin" => Random.new(1).bytes(4 * Input::Stream::BLOCK))))
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
    assert_in_delta 1.0, input.progress
  end

  def test_progress_of_a_zip_among_other_files
    paths = [write("a.jsonl", "1\n" * 1000), write("b.zip", zip("b.bin" => Random.new(2).bytes(200_000))),
             write("c.jsonl", "3\n" * 1000)]
    input = Input.new(paths)
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert_equal values, values.sort
    assert_in_delta 1.0, input.progress
  end

  private

  def zip(entries) = ZipBuilder.build(entries)

  def documents(target)
    result = []
    Input.new(target).each_document { |stream, name| result << [name, stream.read] }
    result
  end

  # entries: name => content.
  def tar(entries)
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |writer|
      entries.each { |name, content| writer.add_file_simple(name, 0o644, content.bytesize) { it.write(content) } }
    end
    io.string
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

  # The reading end of a pipe that a thread fills with bytes.
  def piped(bytes)
    reader, writer = IO.pipe
    Thread.new do
      writer.write(bytes)
    rescue Errno::EPIPE, IOError
      nil
    ensure
      writer.close
    end
    reader
  end

  def temporary_files = Dir.children(@tmp).count { it.start_with?("metacrunch-zip") }

  def without_temporary_files(&)
    override(Tempfile, :create, ->(*, **) { flunk("a temporary file was created") }, &)
  end

end
