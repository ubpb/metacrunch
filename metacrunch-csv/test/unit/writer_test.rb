# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Helpers

  Writer = Metacrunch::Csv::Writer

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Options

  def test_new_touches_no_file
    path = File.join(@dir, "out.csv")
    Writer.new(path)

    refute_path_exists path
  end

  def test_flush_writes_the_rows_so_far_to_the_file
    path = File.join(@dir, "out.csv")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write({"id" => "1"}, ctx)
    writer.flush

    assert_equal "id\n1\n", File.read(path)
  ensure
    writer&.close
  end

  def test_invalid_options_are_argument_errors
    [{columns: "id"}, {header: "yes"}, {bom: nil}, {encoding: "Klingon"}, {quote_char: ","}].each do |options|
      assert_raises(ArgumentError) { Writer.new(StringIO.new, **options) }
    end
  end

  def test_a_bom_needs_a_unicode_encoding
    error = assert_raises(ArgumentError) { Writer.new(StringIO.new, encoding: "Windows-1252", bom: true) }

    assert_equal "bom: true needs UTF-8, UTF-16LE or UTF-16BE, got Windows-1252", error.message
  end

  # Columns and header

  def test_the_first_record_defines_the_columns
    assert_equal "id,title\n1,Moby\n2,\n", written([{"id" => "1", "title" => "Moby"}, {"id" => "2"}])
  end

  def test_columns_select_and_order_the_keys
    assert_equal "title,id\nMoby,1\n", written([{"id" => "1", "year" => "1851", "title" => "Moby"}],
                                               columns: ["title", "id"])
  end

  def test_columns_name_the_header
    assert_equal "ID,Titel\n1,Moby\n", written([{"id" => "1", "title" => "Moby"}],
                                               columns: {"ID" => "id", "Titel" => "title"})
  end

  def test_a_new_key_without_columns_stops_the_run
    error = write_error([{"id" => "1"}, {"id" => "2", "isbn" => "x"}])

    assert_match(/\Arecord at position 2 has the key "isbn", which the first record does not have/, error.message)
  end

  def test_arrays_without_columns_have_no_header
    assert_equal "1,Moby\n", written([["1", "Moby"]])
  end

  def test_arrays_with_columns_have_its_header
    assert_equal "id,title\n1,Moby\n", written([["1", "Moby"]], columns: ["id", "title"])
  end

  def test_header_false_writes_no_header_row
    assert_equal "1\n", written([{"id" => "1"}], header: false)
  end

  def test_an_empty_run_with_columns_writes_the_header
    assert_equal "id,title\n", written([], columns: ["id", "title"])
  end

  def test_an_empty_run_without_columns_writes_nothing
    assert_empty written([])
  end

  # Values

  def test_values_by_type
    assert_equal "s,1,1.5,true,false,,\"\"\n", written([["s", 1, 1.5, true, false, nil, ""]])
  end

  def test_other_values_are_errors
    error = write_error([{"id" => "1", "date" => Time.now}])

    assert_equal 'record at position 1: column "date" is a Time; turn it into a String in a step', error.message
  end

  def test_errors_in_array_records_name_the_column_number
    error = write_error([[1, [2]]])

    assert_equal "record at position 1: column 2 is an Array; turn it into a String in a step", error.message
  end

  # As from a database's NUMERIC column; to_s would give "0.12345e3".
  def test_big_decimals_are_written_as_decimals
    assert_equal "123.45,100000000000000000000.0\n", written([[BigDecimal("123.45"), BigDecimal("1e20")]])
  end

  def test_invalid_strings_are_errors
    error = write_error([{"t" => "a\xFFb".dup.force_encoding(Encoding::UTF_8)}])

    assert_equal 'record at position 1: column "t" is not valid UTF-8', error.message
  end

  def test_binary_strings_without_utf8_form_are_errors
    error = write_error([{"t" => "M\xFCller".b}])

    assert_equal 'record at position 1: column "t" has no UTF-8 form (it is ASCII-8BIT)', error.message
  end

  def test_strings_in_other_encodings_are_converted
    assert_equal "t\nMüller\n".b, written([{"t" => "Müller".encode(Encoding::ISO_8859_1)}])
  end

  def test_fields_are_quoted_only_where_needed
    assert_equal %(plain,"a,b","say ""hi""","two\nlines"\n), written([["plain", "a,b", %(say "hi"), "two\nlines"]])
  end

  # A blank line would be skipped by readers.
  def test_a_row_of_one_empty_field_is_not_a_blank_line
    records = [{"note" => "a"}, {"note" => nil}, {}, {"note" => "b"}]

    assert_equal %(note\na\n""\n""\nb\n), written(records, columns: ["note"])
    assert_equal %(""\n""\n), written([[], [nil]])
  end

  # Encodings and BOM

  def test_windows1252_for_excel
    bytes = written([{"id" => "1", "name" => "Müller"}], col_sep: ";", encoding: "Windows-1252")

    assert_equal "id;name\n1;M\xFCller\n".b, bytes
  end

  def test_a_character_missing_in_the_encoding_is_an_error
    error = write_error([{"name" => "€uro"}], encoding: "ISO-8859-1")

    assert_match(/\Arecord at position 1 has a character ISO-8859-1 cannot represent/, error.message)
  end

  def test_a_header_name_missing_in_the_encoding_is_an_error
    error = write_error([], columns: ["€"], encoding: "ISO-8859-1")

    assert_match(/\Athe header has a character ISO-8859-1 cannot represent/, error.message)
  end

  def test_bom_for_utf8
    assert_equal "\xEF\xBB\xBFid\n1\n".b, written([{"id" => "1"}], bom: true)
  end

  def test_bom_for_utf16le
    bytes = written([], columns: ["id"], encoding: "UTF-16LE", bom: true)

    assert_equal "\uFEFFid\n".encode(Encoding::UTF_16LE).b, bytes
  end

  def test_an_empty_run_with_bom_writes_the_bom_only
    assert_equal "\xEF\xBB\xBF".b, written([], bom: true)
  end

  # Targets and batches

  def test_a_gz_path_is_compressed
    path = File.join(@dir, "out.csv.gz")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write({"id" => "1"}, ctx)
    writer.close

    assert_equal "id\n1\n", Zlib.gunzip(File.binread(path))
  end

  def test_dash_is_stdout
    out, = capture_io do
      writer = Writer.new("-")
      writer.open(nil)
      writer.write({"id" => "1"}, ctx)
      writer.close
    end

    assert_equal "id\n1\n", out
  end

  def test_a_batch_is_written_like_single_records
    io = StringIO.new("".b)
    writer = Writer.new(io)
    writer.open(nil)
    writer.write_batch([{"id" => "1"}, {"id" => "2"}], [ctx(1), ctx(2)])
    writer.close

    assert_equal "id\n1\n2\n", io.string
  end

  def test_an_error_in_a_batch_names_its_record
    writer = Writer.new(StringIO.new("".b), encoding: "ISO-8859-1")
    writer.open(nil)
    error = assert_raises(Metacrunch::Error) do
      writer.write_batch([{"n" => "a"}, {"n" => "b"}, {"n" => "€"}], [ctx(1), ctx(2), ctx(3)])
    end

    assert_match(/\Arecord at position 3 has a character ISO-8859-1 cannot represent/, error.message)
  end

end
