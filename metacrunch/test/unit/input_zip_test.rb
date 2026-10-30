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

  # The copy has no name in TMPDIR, not even while it is read, so nothing
  # is left when the process is killed.
  def test_stdin_and_pipes_go_through_an_anonymous_temporary_file
    archive = zip("a.csv" => "1\n")
    original = $stdin
    $stdin = piped(archive)
    seen = []
    copies = spying_on_temporary_files do
      Input.new("-", unpack: Input::UNPACK).each_document { |stream, name| seen << [name, stream.read, temporary_files] }
      Input.new(piped(archive), unpack: Input::UNPACK).each_document { |stream, name| seen << [name, stream.read, temporary_files] }
    end

    assert_equal [["-:a.csv", "1\n", 0], ["IO:a.csv", "1\n", 0]], seen
    assert_equal 2, copies.size
  ensure
    $stdin = original
  end

  def test_the_temporary_file_is_closed_after_an_error
    archive = ZipBuilder.build([{name: "a.csv", data: "1\n", crc: 1}])
    copies = spying_on_temporary_files do
      assert_raises(Metacrunch::InputError) { documents(piped(archive)) }
    end

    assert_equal [true], copies.map(&:closed?)
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
    Input.new(path, unpack: Input::UNPACK).each_document { |stream, _name| heads << stream.read(2) }

    assert_equal ["aa", "bb"], heads

    broken = write("broken.zip", ZipBuilder.build([{name: "a.txt", data: "a" * 3000, crc: 1}]))
    error = assert_raises(Metacrunch::InputError) { Input.new(broken, unpack: Input::UNPACK).each_document { |stream, _| stream.read(2) } }

    assert_equal "#{broken}:a.txt: broken zip archive (wrong CRC32)", error.message
  end

  def test_breaking_out_removes_the_temporary_file
    Input.new(piped(zip("a.csv" => "1\n", "b.csv" => "2\n")), unpack: Input::UNPACK).each_document { break }

    assert_equal 0, temporary_files
  end

  def test_an_interrupt_removes_the_temporary_file
    queue = Queue.new
    reading = Queue.new
    thread = Thread.new do
      Input.new(piped(zip("a.csv" => "1\n")), unpack: Input::UNPACK).each_document do
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

    assert_equal "-: no space left on device for a temporary copy in #{@tmp} (TMPDIR)", error.message
  ensure
    $stdin = original
  end

  def test_an_error_creating_the_temporary_file_names_the_target
    {Errno::EMFILE.new => "-: too many open files for a temporary copy in #{@tmp} (TMPDIR)",
     ArgumentError.new("could not find a temporary directory") => "-: could not find a temporary directory"}
      .each do |exception, message|
      original = $stdin
      $stdin = piped(zip("a.csv" => "1\n"))
      error = override(Tempfile, :create, ->(*, **) { raise exception }) do
        assert_raises(Metacrunch::InputError) { documents("-") }
      end

      assert_equal message, error.message
    ensure
      $stdin = original
    end
  end

  # An error of the block is the block's, not one of the temporary file.
  def test_errors_of_the_block_are_not_renamed
    error = assert_raises(Errno::EACCES) do
      Input.new(piped(zip("a.csv" => "1\n")), unpack: Input::UNPACK).each_document { raise Errno::EACCES }
    end

    assert_kind_of SystemCallError, error
    assert_equal 0, temporary_files
  end

  def test_progress_of_a_zip_path
    input = Input.new(write("random.zip", zip("a.bin" => Random.new(1).bytes(4 * Input::Stream::BLOCK))), unpack: Input::UNPACK)
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
    assert_in_delta 1.0, input.progress
  end

  def test_progress_of_a_zip_among_other_files
    paths = [write("a.jsonl", "1\n" * 1000), write("b.zip", zip("b.bin" => Random.new(2).bytes(200_000))),
             write("c.jsonl", "3\n" * 1000)]
    input = Input.new(paths, unpack: Input::UNPACK)
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert_equal values, values.sort
    assert_in_delta 1.0, input.progress
  end

  # Input does not judge what an archive holds: a workbook, an EPUB or a
  # jar is a zip archive like any other, and whether its files suit the
  # reader is up to whoever chose the input.
  def test_office_files_and_other_packages_are_archives
    xlsx = write("data.xlsx", zip("[Content_Types].xml" => "x", "xl/workbook.xml" => "w"))
    epub = write("book.epub", zip("mimetype" => "application/epub+zip", "META-INF/container.xml" => "c"))
    tar = write("dump.tar", tar("a.xlsx" => zip("[Content_Types].xml" => "x", "xl/workbook.xml" => "w")))

    assert_equal ["#{xlsx}:[Content_Types].xml", "#{xlsx}:xl/workbook.xml"], documents(xlsx).map(&:first)
    assert_equal ["#{epub}:mimetype", "#{epub}:META-INF/container.xml"], documents(epub).map(&:first)
    assert_equal ["#{tar}:a.xlsx:[Content_Types].xml", "#{tar}:a.xlsx:xl/workbook.xml"], documents(tar).map(&:first)
  end

  def test_encrypted_entries
    [{flags: 1}, {flags: 64}, {method: 99}].each do |options|
      path = write("secret.zip", ZipBuilder.build([{name: "a.txt", data: "a", **options}]))

      assert_equal "#{path}:a.txt: is encrypted, which metacrunch cannot read; decrypt it first, e.g. 7z x #{path}",
                   error(path)
    end
  end

  def test_other_compression_methods
    {9 => "Deflate64", 12 => "bzip2", 14 => "LZMA", 93 => "zstd", 95 => "xz", 98 => "PPMd",
     42 => "method 42"}.each do |method, label|
      path = write("packed.zip", ZipBuilder.build([{name: "a.txt", data: "a", method:}]))

      assert_equal "#{path}:a.txt: is compressed with #{label}, which metacrunch cannot read; unpack it first, " \
                   "e.g. 7z x #{path}", error(path)
    end
  end

  def test_unsupported_entries_are_refused_before_the_first_document
    path = write("mixed.zip", ZipBuilder.build([{name: "a.txt", data: "a"}, {name: "b.txt", data: "b", method: 12}]))
    yielded = []
    assert_raises(Metacrunch::InputError) { Input.new(path, unpack: Input::UNPACK).each_document { |_stream, name| yielded << name } }

    assert_empty yielded
  end

  def test_skipped_entries_are_not_checked
    path = write("skipped.zip", ZipBuilder.build([{name: "d/", flags: 1, method: 0}, {name: ".hidden", flags: 1},
                                                  {name: "a.txt", data: "a"}]))

    assert_equal [["#{path}:a.txt", "a"]], documents(path)
  end

  def test_an_encrypted_central_directory
    path = write("hidden.zip", ZipBuilder.build([{name: "a.txt", data: "a", flags: 0x2000}]))

    assert_equal "#{path}: is encrypted, which metacrunch cannot read; decrypt it first, e.g. 7z x #{path}",
                 error(path)
  end

  def test_hints_inside_other_archives_and_on_stdin
    tar_path = write("dump.tar", tar("a.zip" => ZipBuilder.build([{name: "x.txt", data: "x", method: 12}])))
    original = $stdin
    $stdin = piped(ZipBuilder.build([{name: "y.txt", data: "y", flags: 1}]))

    assert_equal "#{tar_path}:a.zip:x.txt: is compressed with bzip2, which metacrunch cannot read; unpack it first, " \
                 "e.g. with 7z", error(tar_path)
    assert_equal "-:y.txt: is encrypted, which metacrunch cannot read; decrypt it first, e.g. with 7z", error("-")
  ensure
    $stdin = original
  end

  def test_paths_are_quoted_in_hints
    path = write("my dump.zip", ZipBuilder.build([{name: "a.txt", data: "a", flags: 1}]))

    assert error(path).end_with?("e.g. 7z x #{path.gsub(" ", "\\ ")}")
  end

  private

  def zip(entries) = ZipBuilder.build(entries)

  def error(target) = assert_raises(Metacrunch::InputError) { documents(target) }.message

  def documents(target)
    result = []
    Input.new(target, unpack: Input::UNPACK).each_document { |stream, name| result << [name, stream.read] }
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

  # Runs the block and returns the temporary files Tempfile.create made.
  def spying_on_temporary_files(&)
    copies = []
    create = Tempfile.method(:create)
    override(Tempfile, :create, ->(*args, **options) { create.call(*args, **options).tap { copies << it } }, &)
    copies
  end

end
