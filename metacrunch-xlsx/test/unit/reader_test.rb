# frozen_string_literal: true

require "test_helper"
require "rubygems/package"

class ReaderTest < Minitest::Test

  include Helpers

  Reader = Metacrunch::Xlsx::Reader
  ParseError = Metacrunch::Xlsx::ParseError
  RECORDS = [{"id" => "00123", "title" => "Moby-Dick", "year" => 1851, "price" => 9.5, "lent" => true},
             {"id" => "00124", "title" => "Emma", "year" => 1815, "price" => nil, "lent" => false}].freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_reads_the_first_sheet_as_hashes
    assert_equal RECORDS, Reader.new(xlsx(RECORDS)).each.to_a
  end

  def test_headers_array_and_false
    path = workbook(row(1, "a", 1) + row(2, "b", 2))

    assert_equal [{"x" => "a", "y" => 1}, {"x" => "b", "y" => 2}], read(path, headers: ["x", "y"])
    assert_equal [["a", 1], ["b", 2]], read(path, headers: false)
  end

  def test_skip_counts_sheet_rows
    path = workbook(row(1, "Books") + row(3, "id", "title") + row(4, 1, "Emma"))

    assert_equal [{"id" => 1, "title" => "Emma"}], read(path, skip: 2)
    assert_equal [["id", "title"], [1, "Emma"]], read(path, skip: 1, headers: false)
  end

  def test_header_values_become_strings
    data = %(<row r="1"><c r="A1"><v>2024</v></c><c r="B1"><v>1.5</v></c><c r="C1" s="1"><v>45597</v></c>) +
           %(<c r="D1" t="b"><v>1</v></c><c r="E1" t="e"><v>#N/A</v></c></row>) + row(2, 1, 2, 3, 4, 5)

    assert_equal [{"2024" => 1, "1.5" => 2, "2024-11-01" => 3, "TRUE" => 4, "#N/A" => 5}],
                 read(workbook(data, xfs: [0, 14]))
  end

  def test_an_empty_or_duplicate_column_name_stops_the_run
    empty = workbook(row(1, "x") + row(3, "id", "title", nil, "year"))
    twice = workbook(row(3, "Titel", "Jahr", "Titel"))

    assert_equal("#{empty}:Sheet1: the header row (row 3) has an empty column name (column C)",
                 error { read(empty, skip: 2) })
    assert_equal(%(#{twice}:Sheet1: the header row (row 3) names the column "Titel" twice), error { read(twice) })
  end

  def test_a_header_row_that_cannot_be_read_stops_the_run
    path = workbook(%(<row r="1"><c r="A1" t="s"><v>7</v></c></row>))

    assert_equal("#{path}:Sheet1: the header row (row 1) cannot be read (cell A1: shared string 7, the table has 0)",
                 error { read(path) })
  end

  def test_a_value_right_of_the_header_is_an_invalid_record
    records = read(workbook(row(1, "a", "b") + row(7, 1, nil, nil, nil, nil, nil, nil, 8) + row(8, 1, 2)))

    assert_equal [1, nil, nil, nil, nil, nil, nil, 8], records.first.raw
    assert_equal ParseError.new("row 7 has a value in column H, the header ends at column B"), records.first.error
    assert_equal({"a" => 1, "b" => 2}, records.last)
  end

  def test_a_defective_cell_is_an_invalid_record
    cell = %(<c r="B2" t="b"><v>2</v></c>)
    records = read(workbook(row(1, "a", "b") + %(<row r="2"><c r="A2"><v>1</v></c>#{cell}</row>)))

    assert_equal [Metacrunch::InvalidRecord.new(raw: [1, cell], error: ParseError.new(%(cell B2: boolean "2")))],
                 records
  end

  def test_an_empty_sheet_gives_no_records
    assert_empty read(workbook(""))
    assert_empty read(xlsx([]))
  end

  def test_sheet_by_name_and_position_and_each_workbook_its_own_header
    first = workbook(row(1, "a"), sheets: {"Front" => row(1, "x"), "Daten" => row(1, "id") + row(2, 1)})
    second = workbook(row(1, "a"), sheets: {"Front" => "", "Daten" => row(1, "nr") + row(2, 2)})

    assert_equal [{"id" => 1}, {"nr" => 2}], read([first, second], sheet: "Daten")
    assert_equal [{"id" => 1}, {"nr" => 2}], read([first, second], sheet: 2)
  end

  def test_invalid_options
    {{sheet: 0} => "sheet must be a name or a position from 1 (sheets count from 1), got 0",
     {sheet: ""} => %(sheet must be a name or a position from 1 (sheets count from 1), got ""),
     {sheet: 1.5} => "sheet must be a name or a position from 1 (sheets count from 1), got 1.5",
     {headers: ["a", "a"]} => %(headers must be true, false or an Array of unique, non-empty Strings, got ["a", "a"]),
     {skip: -1} => "skip must be an Integer of 0 or more, got -1",
     {unpack: [:gzip, :zip]} => "unpack must not name :zip: a workbook is a zip archive, which is read as one",
     {unpack: [:bzip2]} => "unpack must be an Array of :gzip, :tar and :zip, got [:bzip2]"}.each do |options, message|
      assert_equal message, assert_raises(ArgumentError) { Reader.new("a.xlsx", **options) }.message
    end
  end

  def test_xls_and_other_files_are_refused
    xls = File.join(@dir, "old.xls")
    File.binwrite(xls, "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1#{"\0" * 504}".b)
    csv = File.join(@dir, "data.csv")
    File.write(csv, "id,title\n")

    assert_equal("#{xls}: is an Excel 97-2003 workbook (.xls) or an encrypted workbook, which metacrunch cannot " \
                 "read; save it as .xlsx first", error { read(xls) })
    assert_equal("#{csv}: is not an XLSX workbook", error { read(csv) })
  end

  def test_stdin_gzip_and_tar
    bytes = File.binread(xlsx(RECORDS))
    gz = File.join(@dir, "books.xlsx.gz")
    File.binwrite(gz, Zlib.gzip(bytes))
    tar = File.join(@dir, "books.tar")
    File.binwrite(tar, tar_of("books.xlsx" => bytes))

    assert_equal RECORDS * 3, read([StringIO.new(bytes), gz, tar], unpack: [:gzip, :tar])
    assert_match(/is a tar archive; to read its files, pass unpack: \[:gzip, :tar\]/, error { read(tar) })
  end

  def test_progress
    reader = Reader.new(xlsx(RECORDS))
    values = reader.each.map { reader.progress }

    assert_equal [1.0, 1.0], values
    assert_in_delta 1.0, reader.progress
  end

  # Excel writes the shared strings and the styles after the sheet; the
  # progress follows the sheet, not the parts read before its first row.
  def test_progress_follows_the_sheet
    random = Random.new(3)
    data = (1..20_000).map do |number|
      %(<row r="#{number}"><c r="A#{number}" t="s"><v>#{number % 100}</v></c>) +
        %(<c r="B#{number}"><v>#{random.rand}</v></c></row>)
    end.join
    path = workbook(data, strings: Array.new(100) { "<t>#{random.bytes(300).unpack1("H*")}</t>" }, xfs: [0])
    reader = Reader.new(path, headers: false)
    values = reader.each.map { reader.progress }

    assert_operator values.first, :<, 0.5
    assert_equal values.sort, values
  end

  private

  def read(targets, **) = Reader.new(targets, **).each.to_a

  def error(&) = assert_raises(Metacrunch::InputError, &).message

  def workbook(data, sheets: nil, **)
    path = File.join(@dir, "book-#{Dir.children(@dir).size}.xlsx")
    File.binwrite(path, WorkbookBuilder.build(sheets: sheets || {"Sheet1" => data}, **))
    path
  end

  # A row of numbers and inline strings; nil leaves a cell out.
  def row(number, *values)
    cells = values.each_with_index.filter_map do |value, index|
      ref = "#{Metacrunch::Xlsx::Cells.column(index)}#{number}"
      next if value.nil?

      next %(<c r="#{ref}"><v>#{value}</v></c>) unless value.is_a?(String)

      %(<c r="#{ref}" t="inlineStr"><is><t>#{value}</t></is></c>)
    end
    %(<row r="#{number}">#{cells.join}</row>)
  end

  def tar_of(entries)
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |writer|
      entries.each { |name, content| writer.add_file_simple(name, 0o644, content.bytesize) { it.write(content) } }
    end
    io.string
  end

end
