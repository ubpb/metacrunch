# frozen_string_literal: true

require "test_helper"

class ReaderTest < Minitest::Test

  include Helpers

  Reader = Metacrunch::Csv::Reader

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Options

  def test_new_touches_no_file
    assert_instance_of Reader, Reader.new(File.join(@dir, "missing.csv"))
  end

  def test_headers_must_be_true_false_or_names
    [nil, "id", [], ["a", "a"], ["", "b"], [:a]].each do |headers|
      assert_raises(ArgumentError) { Reader.new("data.csv", headers:) }
    end
  end

  def test_options_are_checked_by_new
    assert_raises(ArgumentError) { Reader.new("data.csv", encoding: "UTF-16") }
    assert_raises(ArgumentError) { Reader.new("data.csv", col_sep: "") }
  end

  # UTF-8 and single-byte encodings are parsed as bytes.
  def test_quote_char_must_be_one_byte_for_reading
    error = assert_raises(ArgumentError) { Reader.new("data.csv", quote_char: "„") }

    assert_equal 'quote_char must be one byte in UTF-8 for reading, got "„"', error.message
  end

  def test_a_quote_char_of_several_bytes_in_utf16
    bytes = "id,t\n1,„a,b„\n".encode(Encoding::UTF_16LE)

    assert_equal [{"id" => "1", "t" => "a,b"}], read(bytes, quote_char: "„", encoding: "UTF-16LE")
  end

  # Records

  def test_records_are_hashes_with_string_keys_and_values
    assert_equal [{"id" => "1", "title" => "Moby"}], read("id,title\n1,Moby\n")
  end

  def test_empty_fields_are_empty_strings_and_missing_fields_nil
    assert_equal [{"a" => "1", "b" => "", "c" => ""}, {"a" => "2", "b" => nil, "c" => nil}],
                 read(%(a,b,c\n1,,""\n2\n))
  end

  def test_values_are_never_converted
    assert_equal [{"id" => "00123", "isbn" => "0306406152", "year" => "1851"}],
                 read("id,isbn,year\n00123,0306406152,1851\n")
  end

  def test_blank_lines_are_skipped
    assert_equal [{"id" => "1"}, {"id" => "2"}], read("id\n\n1\n\n2\n\n")
  end

  def test_a_header_row_only_and_an_empty_document_yield_nothing
    assert_empty read("id,title\n")
    assert_empty read("")
  end

  def test_headers_false_yields_arrays
    assert_equal [["1", ""], ["2"]], read("1,\n2\n", headers: false)
  end

  def test_headers_names_the_columns_of_a_file_without_header_row
    assert_equal [{"id" => "1", "title" => "Moby"}, {"id" => "2", "title" => nil}],
                 read("1,Moby\n2\n", headers: ["id", "title"])
  end

  def test_col_sep_and_quote_char
    assert_equal [{"id" => "1", "title" => "a;b"}], read("id;title\n1;'a;b'\n", col_sep: ";", quote_char: "'")
  end

  def test_quoted_line_breaks_and_quotes
    assert_equal [{"id" => "1", "title" => %(a\n"b")}], read(%(id,title\n1,"a\n""b"""\n))
  end

  def test_crlf_line_ends
    assert_equal [{"id" => "1", "title" => "Moby"}], read("id,title\r\n1,Moby\r\n")
  end

  def test_cr_line_ends
    assert_equal [{"id" => "1", "t" => "a"}, {"id" => "2", "t" => "b"}], read("id,t\r1,a\r2,b\r")
  end

  # Ruby's csv would take the first line break, also one inside quotes.
  def test_the_row_separator_is_the_first_line_break_outside_quotes
    assert_equal [{"a\nb" => "1", "c" => "2"}], read(%("a\nb",c\r\n1,2\r\n))
  end

  def test_the_row_separator_in_utf16
    bytes = %("a\nb",1\r\nc,2\r\n).encode(Encoding::UTF_16LE)

    assert_equal [["a\nb", "1"], ["c", "2"]], read(bytes, headers: false, encoding: "UTF-16LE")
  end

  # Without a line break in its first 64 KiB, Ruby's csv decides.
  def test_a_first_row_longer_than_the_sample
    long = "x" * 70_000

    assert_equal [[long, "1"], ["c", "2"]], read("#{long},1\r\nc,2\r\n", headers: false)
  end

  def test_a_quoted_value_longer_than_a_block
    big = "x" * 100_000

    assert_equal [{"id" => "1", "t" => big}, {"id" => "2", "t" => "ok"}], read(%(id,t\n1,"#{big}"\n2,ok\n))
  end

  # Encodings

  def test_the_utf8_bom_is_removed
    assert_equal [{"id" => "1"}], read("\xEF\xBB\xBFid\n1\n")
  end

  def test_windows1252_is_read_as_utf8
    records = read("id;name\n1;M\xFCller\n", col_sep: ";", encoding: "Windows-1252")

    assert_equal [{"id" => "1", "name" => "Müller"}], records
    assert_equal Encoding::UTF_8, records.first["name"].encoding
  end

  def test_excel_unicode_text_is_read_as_utf8
    bytes = "\uFEFFid\tname\n1\tMüller\n".encode(Encoding::UTF_16LE)
    records = read(bytes, col_sep: "\t", encoding: "UTF-16LE")

    assert_equal [{"id" => "1", "name" => "Müller"}], records
    assert_equal [Encoding::UTF_8], records.first.flatten.map(&:encoding).uniq
  end

  def test_utf16be_with_bom
    bytes = "\uFEFFid\n1\n".encode(Encoding::UTF_16BE)

    assert_equal [{"id" => "1"}], read(bytes, encoding: "UTF-16BE")
  end

  def test_utf16_characters_split_between_blocks
    text = +"id\tt\n"
    4000.times { text << "#{it}\t#{"x" * (it % 7)}😀\n" }
    records = read(text.encode(Encoding::UTF_16LE), col_sep: "\t", encoding: "UTF-16LE")

    assert_equal 4000, records.size
    assert_equal({"id" => "3999", "t" => "xx😀"}, records.last)
  end

  # Rows that cannot be read

  def test_wrong_quoting_is_an_invalid_record_and_reading_goes_on
    records = read(%(id,t\n1,"bad"quote\n2,ok\n))
    invalid = records.first

    assert_equal %(1,"bad"quote), invalid.raw
    assert_instance_of CSV::MalformedCSVError, invalid.error
    assert_equal({"id" => "2", "t" => "ok"}, records.last)
  end

  def test_invalid_bytes_are_an_invalid_record
    records = read("id,t\n1,a\xFFb\n2,ok\n")

    assert_equal "1,a\uFFFDb", records.first.raw
    assert_instance_of CSV::InvalidEncodingError, records.first.error
    assert_equal({"id" => "2", "t" => "ok"}, records.last)
  end

  def test_windows1252_read_as_utf8_names_the_encoding
    invalid = read("id\nM\xFCller\n").first

    assert_equal "Invalid byte sequence in UTF-8 in line 2.", invalid.error.message
  end

  def test_a_byte_without_utf8_form_is_an_invalid_record
    records = read("id\n\x81\n2\n", encoding: "Windows-1252")

    assert_instance_of Encoding::UndefinedConversionError, records.first.error
    assert_equal({"id" => "2"}, records.last)
  end

  def test_more_fields_than_columns_is_an_invalid_record
    invalid = read("a,b\n1,2,3\n").first

    assert_equal "1,2,3", invalid.raw
    assert_instance_of Metacrunch::Csv::ParseError, invalid.error
    assert_equal "row has 3 fields, the header 2", invalid.error.message
  end

  def test_an_unclosed_quote_takes_the_rest_of_the_document
    records = read(%(id,t\n1,ok\n2,"open\n3,x\n))

    assert_equal 2, records.size
    assert_equal %(2,"open\n3,x), records.last.raw
  end

  def test_invalid_utf16_stops_the_document
    bytes = "id\n".encode(Encoding::UTF_16LE).b + "\x00\xD8\n\x00".b
    error = assert_raises(Metacrunch::InputError) { read(bytes, encoding: "UTF-16LE") }

    assert_equal "StringIO: the data is not valid UTF-16LE", error.message
  end

  # The header row

  def test_a_column_named_twice_is_an_input_error
    path = file("data.csv", "a,b,a\n1,2,3\n")
    error = assert_raises(Metacrunch::InputError) { Reader.new(path).each.to_a }

    assert_equal %(#{path}: the header row names the column "a" twice), error.message
  end

  def test_an_empty_column_name_is_an_input_error
    path = file("data.csv", "a,b,\n1,2,3\n")
    error = assert_raises(Metacrunch::InputError) { Reader.new(path).each.to_a }

    assert_equal "#{path}: the header row has an empty column name (column 3)", error.message
  end

  def test_an_unreadable_header_row_is_an_input_error
    error = assert_raises(Metacrunch::InputError) { read(%(a,"b"c\n1,2\n)) }

    assert_match(/\AStringIO: the header row cannot be read \(Any value after quoted field/, error.message)
  end

  # Inputs

  def test_gzip_files
    path = file("data.csv.gz", Zlib.gzip("id\n1\n"))

    assert_equal [{"id" => "1"}], Reader.new(path).each.to_a
  end

  def test_every_member_of_a_tar_archive_has_its_own_header_row
    archive = tar("a.csv" => "id\n1\n", "b.csv" => "name\nMoby\n")

    assert_equal [{"id" => "1"}, {"name" => "Moby"}], read(archive)
  end

  def test_dash_is_stdin
    $stdin = StringIO.new("id\n1\n")

    assert_equal [{"id" => "1"}], Reader.new("-").each.to_a
  ensure
    $stdin = STDIN
  end

  def test_an_array_of_targets
    paths = [file("a.csv", "id\n1\n"), file("b.csv", "id\n2\n")]

    assert_equal [{"id" => "1"}, {"id" => "2"}], Reader.new(paths).each.to_a
  end

  def test_progress_is_the_inputs
    reader = Reader.new(file("data.csv", "id\n1\n"))
    reader.each.to_a

    assert_in_delta 1.0, reader.progress
  end

  def test_each_without_a_block_is_an_enumerator
    assert_instance_of Enumerator, Reader.new("data.csv").each
  end

  private

  def file(name, content)
    File.join(@dir, name).tap { File.binwrite(it, content) }
  end

end
