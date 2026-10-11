# frozen_string_literal: true

require "test_helper"
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

  def test_ignores_a_byte_order_mark
    assert_equal [1, 2], read(Reader.new(StringIO.new("﻿1\n2\n")))
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
    reader = Reader.new(write("big.jsonl", "\"#{"x" * 10}\"\n" * 3000))
    values = []
    reader.each { values << reader.progress }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
  end

  def test_reads_gzip_files
    path = File.join(@dir, "in.jsonl.gz")
    Zlib::GzipWriter.open(path) { it.write("{\"a\":1}\n{\"a\":2}\n") }

    assert_equal [{"a" => 1}, {"a" => 2}], read(Reader.new(path))
  end

  def test_dash_reads_stdin
    original = $stdin
    $stdin = StringIO.new("1\n")

    assert_equal [1], read(Reader.new("-"))
  ensure
    $stdin = original
  end

  def test_breaking_out_closes_the_file
    path = write("in.jsonl", "1\n2\n3\n")
    Reader.new(path).each { break }

    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  private

  def read(reader)
    records = []
    reader.each { records << it }
    records
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

end
