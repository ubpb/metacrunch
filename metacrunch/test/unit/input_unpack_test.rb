# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tempfile"
require "tmpdir"

# What Input unpacks: only the formats unpack: names.
class InputUnpackTest < Minitest::Test

  include Override

  Input = Metacrunch::Input

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_without_unpack_every_target_is_one_document
    gz = write("a.jsonl.gz", Zlib.gzip("1\n"))
    tar = write("a.tar", tar("a.jsonl" => "1\n"))
    zip = write("a.zip", ZipBuilder.build({"a.jsonl" => "1\n"}))

    assert_equal [gz, tar, zip].map { [it, File.binread(it)] }, documents([gz, tar, zip])
  end

  def test_unpack_only_gzip_or_only_tar
    tar_gz = write("a.tar.gz", Zlib.gzip(tar("a.jsonl" => "1\n")))

    assert_equal [[tar_gz, tar("a.jsonl" => "1\n")]], documents(tar_gz, unpack: [:gzip])
    assert_equal [[tar_gz, File.binread(tar_gz)]], documents(tar_gz, unpack: [:tar])
  end

  def test_unpack_tar_and_zip_each
    assert_equal [["#{tar_path}:a.jsonl", "1\n"]], documents(tar_path, unpack: [:tar])
    assert_equal [["#{zip_path}:a.jsonl", "1\n"]], documents(zip_path, unpack: [:zip])
  end

  def test_unpack_all
    tar_gz = write("a.tar.gz", Zlib.gzip(tar("a.jsonl" => "1\n")))

    assert_equal [:gzip, :tar, :zip], Input::UNPACK
    assert_equal [["#{tar_gz}:a.jsonl", "1\n"]], documents(tar_gz, unpack: Input::UNPACK)
  end

  def test_invalid_unpack
    [:gzip, "gzip", [:bzip2], ["gzip"], nil].each do |value|
      error = assert_raises(ArgumentError) { Input.new("a.jsonl", unpack: value) }

      assert_equal "unpack must be an Array of :gzip, :tar and :zip, got #{value.inspect}", error.message
    end
  end

  def test_unreadable_formats_stay_errors
    ["BZh91AY&SY", "\xFD7zXZ\x00", "\x28\xB5\x2F\xFD", "PK\x07\x08PK\x03\x04"].each do |head|
      path = write("data", "#{head}rest".b)

      assert_raises(Metacrunch::InputError) { documents(path) }
    end
  end

  def test_a_zip_without_zip_needs_no_temporary_file
    archive = ZipBuilder.build({"a.jsonl" => "1\n"})
    reader, writer = IO.pipe
    Thread.new do
      writer.write(archive)
    ensure
      writer.close
    end
    result = override(Tempfile, :create, ->(*, **) { flunk("a temporary file was created") }) do
      documents(reader, unpack: [:gzip])
    end

    assert_equal [["IO", archive]], result
  end

  def test_progress_without_unpacking
    input = Input.new(write("random.gz", Zlib.gzip(Random.new(3).bytes(4 * Input::Stream::BLOCK))))
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
    assert_in_delta 1.0, input.progress
  end

  # Archives are unpacked on one level, as tar -x and unzip do.
  def test_an_archive_in_an_archive_is_a_document
    inner_tar = tar("c.jsonl" => "3\n")
    inner_zip = ZipBuilder.build({"d.jsonl" => "4\n"})

    archives = {"tar.tar" => [tar("inner" => inner_tar), inner_tar],
                "zip.zip" => [ZipBuilder.build({"inner" => inner_zip}), inner_zip],
                "tar.zip" => [ZipBuilder.build({"inner" => inner_tar}), inner_tar],
                "zip.tar" => [tar("inner" => inner_zip), inner_zip]}
    archives.each do |name, (bytes, inner)|
      path = write(name, bytes)

      assert_equal [["#{path}:inner", inner]], all(path), name
    end
  end

  def test_gzip_in_archive_members_is_decompressed
    gzipped = Zlib.gzip("1\n")
    tar = write("a.tar", tar("a.jsonl.gz" => gzipped))
    zip = write("a.zip", ZipBuilder.build({"a.jsonl.gz" => gzipped}))

    assert_equal [["#{tar}:a.jsonl.gz", "1\n"], ["#{zip}:a.jsonl.gz", "1\n"]], all([tar, zip])
  end

  # The content of a gzip-compressed archive in an archive is the
  # document: a reader of workbooks gets the workbook.
  def test_a_compressed_archive_in_an_archive_is_its_content
    inner = tar("c.jsonl" => "3\n")
    workbook = ZipBuilder.build({"xl/workbook.xml" => "w"})
    path = write("outer.tar", tar("inner.tar.gz" => Zlib.gzip(inner), "book.xlsx.gz" => Zlib.gzip(workbook)))

    assert_equal [["#{path}:inner.tar.gz", inner], ["#{path}:book.xlsx.gz", workbook]], all(path)
  end

  def test_tar_gz_and_zip_gz_are_unpacked
    tar_gz = write("a.tar.gz", Zlib.gzip(tar("a.jsonl" => "1\n")))
    zip_gz = write("a.zip.gz", Zlib.gzip(ZipBuilder.build({"b.jsonl" => "2\n"})))

    assert_equal [["#{tar_gz}:a.jsonl", "1\n"], ["#{zip_gz}:b.jsonl", "2\n"]], all([tar_gz, zip_gz])
  end

  def test_a_zip_inside_gzip_is_unpacked_from_a_pipe
    reader, writer = IO.pipe
    Thread.new do
      writer.write(Zlib.gzip(ZipBuilder.build({"a.jsonl" => "1\n"})))
    ensure
      writer.close
    end
    created = 0
    create = Tempfile.method(:create)
    result = override(Tempfile, :create, ->(*args, **options) { (created += 1) && create.call(*args, **options) }) do
      all(reader)
    end

    assert_equal [["IO:a.jsonl", "1\n"]], result
    assert_equal 1, created
  end

  def test_no_temporary_file_for_a_zip_in_an_archive
    inner = ZipBuilder.build({"a.jsonl" => "1\n"})
    path = write("a.tar", tar("a.zip" => inner))
    result = override(Tempfile, :create, ->(*, **) { flunk("a temporary file was created") }) { all(path) }

    assert_equal [["#{path}:a.zip", inner]], result
  end

  private

  def all(target) = documents(target, unpack: Input::UNPACK)

  def documents(target, **)
    result = []
    Input.new(target, **).each_document { |stream, name| result << [name, stream.read] }
    result
  end

  def tar(entries)
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |writer|
      entries.each { |name, content| writer.add_file_simple(name, 0o644, content.bytesize) { it.write(content) } }
    end
    io.string
  end

  def tar_path = @tar_path ||= write("plain.tar", tar("a.jsonl" => "1\n"))

  def zip_path = @zip_path ||= write("plain.zip", ZipBuilder.build({"a.jsonl" => "1\n"}))

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
