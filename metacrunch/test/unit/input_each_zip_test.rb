# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tempfile"
require "tmpdir"

# Input#each_zip: every document opened as a zip archive, for sources of
# ZIP-based formats such as workbooks.
class InputEachZipTest < Minitest::Test

  include Override

  Input = Metacrunch::Input
  ARCHIVE = ZipBuilder.build({"a.xml" => "<a/>"})

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_path_is_read_directly
    path = write("a.xlsx", ARCHIVE)

    without_temporary_files { assert_equal [[path, ["a.xml"]]], zips(path) }
  end

  def test_a_seekable_io_is_read_from_its_position
    io = StringIO.new("abc#{ARCHIVE}")
    io.read(3)

    without_temporary_files { assert_equal [["StringIO", ["a.xml"]]], zips(io) }
  end

  def test_stdin_a_pipe_gzip_and_a_tar_member_go_through_a_temporary_file
    gz = write("a.xlsx.gz", Zlib.gzip(ARCHIVE))
    tar = write("b.tar", tar("b.xlsx" => ARCHIVE))
    original = $stdin
    $stdin = piped(ARCHIVE)
    result = nil
    copies = spying_on_temporary_files do
      result = zips("-") + zips(piped(ARCHIVE)) + zips(gz, unpack: [:gzip]) +
               zips(tar, unpack: [:gzip, :tar])
    end

    assert_equal [["-", ["a.xml"]], ["IO", ["a.xml"]], [gz, ["a.xml"]], ["#{tar}:b.xlsx", ["a.xml"]]], result
    assert_equal [true] * 4, copies.map(&:closed?)
  ensure
    $stdin = original
  end

  def test_the_copy_is_closed_after_an_error_in_the_block
    copies = spying_on_temporary_files do
      assert_raises(RuntimeError) { Input.new(piped(ARCHIVE)).each_zip { raise "stop" } }
    end

    assert_equal [true], copies.map(&:closed?)
  end

  def test_a_document_that_is_no_zip_raises_not_zip_with_its_head
    path = write("a.csv", "id,title\n")
    error = assert_raises(Input::NotZip) { zips(path) }

    assert_equal "#{path}: is not a zip archive", error.message
    assert_equal [path, "id,title\n".b], [error.name, error.head]
  end

  def test_a_tar_left_out_of_unpack_is_refused_with_packed_refuse
    path = write("b.tar", tar("b.xlsx" => ARCHIVE))
    error = assert_raises(Metacrunch::InputError) { zips(path, unpack: [:gzip], packed: :refuse) }

    assert_equal "#{path}: is a tar archive; to read its files, pass unpack: [:gzip, :tar] " \
                 "(--unpack gzip,tar with -i)", error.message
  end

  def test_zip_in_unpack_is_refused
    error = assert_raises(ArgumentError) { Input.new("a.xlsx", unpack: [:zip]).each_zip { nil } }

    assert_equal "each_zip opens zip archives itself; leave :zip out of unpack", error.message
  end

  # Detection reads a first block, which is all of a small file.
  def test_progress_counts_what_is_read
    input = Input.new([write("a.xlsx", ARCHIVE), write("b.xlsx", ARCHIVE)])
    values = []
    input.each_zip { |_zip, _name| values << input.progress }

    assert_equal [0.5, 1.0], values
    assert_in_delta 1.0, input.progress
  end

  def test_each_zip_without_a_block_is_an_enumerator
    path = write("a.xlsx", ARCHIVE)

    assert_equal([path], Input.new(path).each_zip.map { |_zip, name| name })
  end

  private

  # name and entry names of every archive.
  def zips(target, **)
    result = []
    Input.new(target, **).each_zip { |zip, name| result << [name, zip.entries.map(&:name)] }
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
