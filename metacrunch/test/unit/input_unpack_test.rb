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

  private

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
