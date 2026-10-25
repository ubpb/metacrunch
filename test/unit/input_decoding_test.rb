# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tmpdir"

class InputDecodingTest < Minitest::Test

  Input = Metacrunch::Input
  Formats = Metacrunch::Input::Formats

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_gzip_is_detected_by_content_whatever_the_name
    path = write("records.jsonl", gzip("1\n2\n"))

    assert_equal [[path, "1\n2\n"]], documents(path)
  end

  def test_gzip_on_stdin_and_from_ios
    original = $stdin
    $stdin = StringIO.new(gzip("in\n"))

    assert_equal [["-", "in\n"]], documents("-")
    assert_equal [["StringIO", "io\n"]], documents(StringIO.new(gzip("io\n")))
  ensure
    $stdin = original
  end

  def test_all_members_are_read
    assert_equal "1\n2\n3\n", content(write("two.gz", gzip("1\n") + gzip("2\n3\n")))
  end

  def test_a_line_may_span_two_gzip_members
    lines = []
    Input.new(write("split.gz", gzip("1\n2") + gzip("3\n"))).each_document { |s, _| lines.concat(s.each_line.to_a) }

    assert_equal ["1\n", "23\n"], lines
  end

  def test_gzip_inside_gzip_up_to_four_layers
    four = 4.times.reduce("x") { |data, _| gzip(data) }
    path = write("five.gz", gzip(four))

    assert_equal "x", content(write("four.gz", four))
    error = assert_raises(Metacrunch::InputError) { documents(path) }
    assert_equal "#{path}: more than 4 layers of gzip and tar", error.message
  end

  def test_broken_and_truncated_gzip
    data = gzip(Random.new(1).bytes(200_000))
    {"broken" => "#{Formats::GZIP}#{"x" * 20}", "truncated" => data.byteslice(0, data.bytesize / 2),
     "no_footer" => data.byteslice(0, data.bytesize - 4)}.each do |name, bytes|
      path = write("#{name}.gz", bytes)
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_match(/\A#{Regexp.escape(path)}: broken gzip data \(.+\)\z/, error.message)
      assert_kind_of Zlib::Error, error.cause
    end
  end

  def test_data_after_the_gzip_data
    ["garbage", "\0" * 512].each_with_index do |rest, index|
      path = write("rest#{index}.gz", gzip("1\n") + rest)
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_equal "#{path}: data after the end of the gzip data", error.message
    end
  end

  def test_stopping_early_raises_nothing_and_prints_nothing
    data = gzip(Random.new(1).bytes(200_000))
    path = write("cut.gz", data.byteslice(0, data.bytesize - 4))
    _, stderr = capture_io do
      verbose = $VERBOSE
      $VERBOSE = true
      Input.new(path).each_document { |stream, _name| break stream.read(10) }
    ensure
      $VERBOSE = verbose
    end

    assert_empty stderr
    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  def test_unsupported_formats_are_named_with_a_hint
    {"BZh91AY&SY" => "is bzip2 compressed, which metacrunch cannot read; decompress it first, e.g. bzip2 -dc",
     "\xFD7zXZ\x00" => "is xz compressed, which metacrunch cannot read; decompress it first, e.g. xz -dc",
     "\x28\xB5\x2F\xFD" => "is zstd compressed, which metacrunch cannot read; decompress it first, e.g. zstd -dc",
     "PK\x03\x04" => "is a zip archive, which metacrunch cannot read; unpack it first, e.g. unzip -p",
     "PK\x05\x06" => "is a zip archive, which metacrunch cannot read; unpack it first, e.g. unzip -p"}
      .each do |head, text|
      path = write("data", "#{head}rest".b)
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_equal "#{path}: #{text} #{path} | metacrunch run job.rb -i -", error.message
    end
  end

  def test_stdin_and_ios_name_file_in_the_hint
    error = assert_raises(Metacrunch::InputError) { documents(StringIO.new("\x28\xB5\x2F\xFDdata".b)) }

    assert_equal "StringIO: is zstd compressed, which metacrunch cannot read; decompress it first, " \
                 "e.g. zstd -dc FILE | metacrunch run job.rb -i -", error.message
  end

  def test_text_that_looks_a_little_like_a_magic_number_is_plain
    ["BZh is not bzip2\n", "PK is not zip\n", "\x1F\x8B but not deflate".b].each do |text|
      assert_equal text, content(write("plain", text))
    end
  end

  def test_short_and_empty_input
    assert_equal [["StringIO", "abc"]], documents(StringIO.new("abc"))
    assert_equal [["StringIO", ""]], documents(StringIO.new(""))
    assert_equal "", content(write("empty.gz", gzip("")))
  end

  def test_progress_of_gzip_is_the_compressed_position
    input = Input.new(write("random.gz", gzip(Random.new(2).bytes(4 * Input::Stream::BLOCK))))
    values = []
    input.each_document { |stream, _name| values << input.progress while stream.read(1000) }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_in_delta 1.0, input.progress
  end

  def test_detect_gzip_and_plain
    assert_equal :gzip, Formats.detect(gzip("x").byteslice(0, Formats::PEEK))
    assert_equal :plain, Formats.detect("{\"a\":1}\n")
    assert_equal :plain, Formats.detect("")
  end

  def test_detect_tar
    header = Gem::Package::TarHeader.new(name: "a", mode: 0o644, size: 0, prefix: "", mtime: 0).to_s

    assert_equal :tar, Formats.detect(header.byteslice(0, Formats::PEEK))
  end

  def test_detect_unsupported_formats
    assert_equal "is zstd compressed", Formats.detect("\x28\xB5\x2F\xFD".b).label
  end

  private

  def gzip(text) = Zlib.gzip(text)

  def documents(target)
    result = []
    Input.new(target).each_document { |stream, name| result << [name, stream.read] }
    result
  end

  def content(path) = documents(path).map(&:last).join

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
