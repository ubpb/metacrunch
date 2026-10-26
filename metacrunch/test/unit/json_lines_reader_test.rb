# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tmpdir"

class JsonLinesReaderTest < Minitest::Test

  Reader = Metacrunch::JsonLines::Reader

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_parses_one_json_value_per_line
    reader = Reader.new(StringIO.new("{\"a\":1}\n42\n\"x\"\n[1,2]\n"))

    assert_equal [{"a" => 1}, 42, "x", [1, 2]], read(reader)
    assert_nil reader.progress
  end

  def test_skips_blank_lines
    assert_equal [1, 2], read(Reader.new(StringIO.new("1\n\n  \n2\n")))
  end

  def test_line_endings_and_a_missing_final_newline
    assert_equal [{"a" => 1}, 2, 3], read(Reader.new(StringIO.new("{\"a\":1}\r\n2\r\n3")))
  end

  def test_ignores_byte_order_marks_also_of_concatenated_files
    assert_equal [1, 2, 3], read(Reader.new(StringIO.new("\uFEFF1\n2\n\uFEFF3\n")))
  end

  def test_lines_with_duplicate_keys_are_invalid
    assert_instance_of Metacrunch::InvalidRecord, read(Reader.new(StringIO.new("{\"a\":1,\"a\":2}\n"))).first
  end

  def test_accepts_pathnames
    assert_equal [1, 2], read(Reader.new(Pathname(write("in.jsonl", "1\n2\n"))))
  end

  def test_invalid_lines_become_invalid_records
    records = read(Reader.new(StringIO.new("1\n{\"id\": 4711, \"ti\n3\n")))
    invalid = records[1]

    assert_equal [1, 3], [records[0], records[2]]
    assert_equal "{\"id\": 4711, \"ti", invalid.raw
    assert_instance_of JSON::ParserError, invalid.error
  end

  def test_invalid_utf8_becomes_an_invalid_record
    records = read(Reader.new(StringIO.new("\"\xFF\"\n\"ok\"\n".b)))

    assert_instance_of Metacrunch::InvalidRecord, records.first
    assert_equal "ok", records.last
  end

  def test_reads_files_and_reports_progress
    reader = Reader.new(write("in.jsonl", "1\n2\n"))

    assert_nil reader.progress
    assert_equal [1, 2], read(reader)
    assert_in_delta 1.0, reader.progress
  end

  def test_progress_grows_while_reading
    reader = Reader.new(write("big.jsonl", "\"#{"x" * 10}\"\n" * 30_000))
    values = reader.enum_for(:each).map { reader.progress }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
  end

  def test_reads_gzip_files
    path = File.join(@dir, "in.jsonl.gz")
    Zlib::GzipWriter.open(path) { it.write("{\"a\":1}\n{\"a\":2}\n") }

    assert_equal [{"a" => 1}, {"a" => 2}], read(Reader.new(path))
  end

  def test_reads_pipes_and_fifos_past_the_progress_sample
    fifo = File.join(@dir, "fifo")
    File.mkfifo(fifo)
    writer = Thread.new { File.write(fifo, "1\n" * 3000) }
    records = read(Reader.new(fifo))
    writer.join

    assert_equal 3000, records.size
  end

  def test_reads_all_members_of_a_gzip_file
    path = File.join(@dir, "two.jsonl.gz")
    File.binwrite(path, gzip("{\"part\":1}\n") + gzip("{\"part\":2}\n{\"part\":3}\n"))

    assert_equal([1, 2, 3], read(Reader.new(path)).map { it["part"] })
  end

  def test_dash_reads_stdin
    original = $stdin
    $stdin = StringIO.new("1\n")

    assert_equal [1], read(Reader.new("-"))
  ensure
    $stdin = original
  end

  def test_reads_arrays_of_targets
    assert_equal [1, 2, 3], read(Reader.new([write("a.jsonl", "1\n2\n"), StringIO.new("3\n")]))
  end

  def test_reads_tar_archives_and_gzip_whatever_the_name
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |tar|
      {"a.jsonl" => "1\n", "b.jsonl.gz" => gzip("2\n")}.each do |name, content|
        tar.add_file_simple(name, 0o644, content.bytesize) { it.write(content) }
      end
    end
    path = File.join(@dir, "records.data")
    File.binwrite(path, gzip(io.string))

    assert_equal [1, 2], read(Reader.new(path))
  end

  def test_reads_gzip_from_stdin
    original = $stdin
    $stdin = StringIO.new(gzip("1\n2\n"))

    assert_equal [1, 2], read(Reader.new("-"))
  ensure
    $stdin = original
  end

  def test_each_without_a_block_is_an_enumerator
    assert_equal [1, 2], Reader.new(StringIO.new("1\n2\n")).each.to_a
  end

  def test_a_missing_file_raises_an_input_error
    path = File.join(@dir, "missing.jsonl")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal "#{path}: no such file", error.message
  end

  def test_breaking_out_closes_the_file
    path = write("in.jsonl", "1\n2\n3\n")
    Reader.new(path).each { break }

    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  private

  def read(reader)
    reader.enum_for(:each).to_a
  end

  def gzip(text)
    io = StringIO.new
    writer = Zlib::GzipWriter.new(io)
    writer.write(text)
    writer.finish
    io.string
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

end
