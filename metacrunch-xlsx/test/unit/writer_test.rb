# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Helpers

  Writer = Metacrunch::Xlsx::Writer

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Options

  def test_new_touches_no_file
    path = File.join(@dir, "out.xlsx")
    Writer.new(path)

    refute_path_exists path
  end

  def test_invalid_sheet_names
    ["", "a" * 32, "a/b", "a[1]", "a:b", "a*", "a?", "a\\b", "'a", "a'", :Sheet1, "a\u0001b", "B\xFCcher".b,
     "a\xFF".dup.force_encoding(Encoding::UTF_8)].each do |sheet|
      assert_raises(ArgumentError) { Writer.new("out.xlsx", sheet:) }
    end
  end

  def test_invalid_widths
    [{"a" => 0}, {"a" => -1}, {"a" => 256}, {"a" => "10"}, [0], "10", 10, [Rational(3, 2)]].each do |widths|
      assert_raises(ArgumentError) { Writer.new("out.xlsx", widths:) }
    end
  end

  def test_invalid_columns_and_header
    assert_raises(ArgumentError) { Writer.new("out.xlsx", columns: "id") }
    assert_raises(ArgumentError) { Writer.new("out.xlsx", header: nil) }
  end

  # Cells and rows

  def test_cells_by_type
    path = xlsx([{"id" => "00123", "n" => 42, "f" => 1.5, "b" => true, "e" => nil, "t" => " a <b> "}])

    assert_equal [["id", "n", "f", "b", "e", "t"], ["00123", 42, 1.5, true, nil, " a <b> "]], rows(path)
  end

  def test_empty_and_blank_strings_are_text_cells
    path = xlsx([{"a" => "", "b" => " ", "c" => "two\nlines"}])

    assert_includes sheet_xml(path), '<c r="A2" t="inlineStr"><is><t></t></is></c>'
    assert_equal [nil, " ", "two\nlines"], rows(path).last
  end

  def test_columns_select_order_and_name
    path = xlsx([{"id" => "1", "year" => 1851, "title" => "Moby"}], columns: {"Titel" => "title", "Nr." => "id"})

    assert_equal [["Titel", "Nr."], ["Moby", "1"]], rows(path)
  end

  def test_arrays_without_columns_have_no_header
    path = xlsx([[1, "x"], [2, "y"]])

    assert_equal [[1, "x"], [2, "y"]], rows(path)
    refute_includes sheet_xml(path), "autoFilter"
  end

  def test_header_false
    path = xlsx([{"id" => "1"}], header: false)

    assert_equal [["1"]], rows(path)
    refute_includes sheet_xml(path), "<pane"
  end

  def test_the_sheet_name
    assert_equal ["Bestand"], Roo::Excelx.new(xlsx([{"id" => "1"}], sheet: "Bestand")).sheets
  end

  def test_a_sheet_name_in_another_encoding_is_written_as_utf8
    path = xlsx([{"id" => "1"}], sheet: "Bücher".encode(Encoding::ISO_8859_1))

    assert_equal ["Bücher"], Roo::Excelx.new(path).sheets
  end

  # Header, widths and parts

  def test_every_part_is_xml
    parts(xlsx([{"a" => 1, "b" => "x"}], sheet: "Tom's")).each_value do |xml|
      assert_instance_of REXML::Document, REXML::Document.new(xml)
    end
  end

  def test_content_types_come_first
    assert_equal "[Content_Types].xml", parts(xlsx([{"a" => 1}])).keys.first
  end

  def test_the_header_is_bold_frozen_and_filtered
    path = xlsx([{"a" => 1, "b" => 2}, {"a" => 3}], sheet: "Bestand")
    xml = parts(path)

    assert_includes xml.fetch("xl/worksheets/sheet1.xml"), '<c r="A1" s="1" t="inlineStr">'
    assert_includes xml.fetch("xl/worksheets/sheet1.xml"), '<autoFilter ref="A1:B3"/>'
    assert_includes xml.fetch("xl/workbook.xml"), "'Bestand'!$A$1:$B$3</definedName>"
  end

  def test_widths_by_name
    xml = sheet_xml(xlsx([{"id" => "1", "title" => "Moby"}], widths: {"title" => 60}))

    assert_includes xml, '<cols><col min="2" max="2" width="60" customWidth="1"/></cols>'
  end

  def test_widths_by_position
    xml = sheet_xml(xlsx([[1, "Moby"]], widths: [8, 60.5]))

    assert_includes xml, '<col min="1" max="1" width="8" customWidth="1"/><col min="2" max="2" width="60.5"'
  end

  def test_a_width_for_an_unknown_column_is_an_error
    error = write_error([{"id" => "1"}], widths: {"Titel" => 60, "Jahr" => 8})

    assert_equal "widths: names columns that do not exist: Titel, Jahr", error.message
  end

  def test_with_columns_an_unknown_width_fails_in_open
    writer = Writer.new(File.join(@dir, "w.xlsx"), columns: ["id"], widths: {"Titel" => 60})

    assert_raises(Metacrunch::Error) { writer.open(nil) }
    writer.close
  end

  # Empty and aborted runs

  def test_an_empty_run_with_columns_has_the_header
    assert_equal [["id", "title"]], rows(xlsx([], columns: ["id", "title"]))
  end

  def test_an_empty_run_without_columns_is_an_empty_sheet
    assert_empty rows(xlsx([]))
  end

  def test_an_aborted_run_keeps_the_rows_so_far
    path = File.join(@dir, "aborted.xlsx")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write({"t" => "ok"}, ctx)
    assert_raises(Metacrunch::Error) { writer.write({"t" => Time.now}, ctx(2)) }
    writer.close

    assert_equal [["t"], ["ok"]], rows(path)
    assert_includes sheet_xml(path), '<autoFilter ref="A1:A2"/>'
  end

  def test_a_header_that_cannot_be_written_still_gives_a_file
    path = File.join(@dir, "header.xlsx")
    writer = Writer.new(path, columns: ["a\u0001"])
    error = assert_raises(Metacrunch::Error) { writer.open(nil) }
    writer.close

    assert_equal 'the header row: column "a\u0001" has a character that XML does not allow', error.message
    assert_empty rows(path)
  end

  def test_close_without_open_and_twice
    writer = Writer.new(File.join(@dir, "never.xlsx"))
    2.times { writer.close }

    refute_path_exists File.join(@dir, "never.xlsx")
  end

  # An IO whose next write holds the writing thread at a gate.
  class GatedIO

    attr_reader :bytes
    attr_writer :gate

    def initialize
      @bytes = "".b
    end

    def write(data)
      gate = @gate
      @gate = nil
      gate&.hold
      @bytes << data.b
      data.bytesize
    end

  end

  # An IO whose reader goes away once it is broken.
  class PipeIO

    attr_writer :broken

    def write(data)
      raise Errno::EPIPE if @broken

      data.bytesize
    end

  end

  # metacrunch run job.rb | head: after SIGPIPE, close finishes nothing and
  # raises nothing.
  def test_close_after_a_broken_pipe
    io = PipeIO.new
    writer = Writer.new(io)
    writer.open(nil)
    io.broken = true
    assert_raises(SignalException) { 10_000.times { writer.write({"t" => "row #{it} " * 20}, ctx) } }

    assert_nil writer.close
  end

  # A record whose lookup is interrupted, as by Ctrl-C.
  class InterruptedRecord < Hash

    def fetch(*) = raise(Interrupt)

  end

  def test_an_interrupt_in_write_still_finishes_the_file
    path = File.join(@dir, "interrupt.xlsx")
    writer = Writer.new(path, columns: ["a"])
    writer.open(nil)
    writer.write({"a" => 1}, ctx)
    assert_raises(Interrupt) { writer.write(InterruptedRecord.new, ctx(2)) }
    writer.close

    assert_equal [["a"], [1]], rows(path)
  end

  # See EntryTest: a signal that wakes the thread inside zlib.
  def test_wakeups_inside_zlib_do_not_break_the_file
    waker = Thread.new { loop { Thread.main.wakeup && Thread.pass } }
    path = xlsx(Array.new(20_000) { {"n" => it, "t" => "row #{it}"} })
    waker.kill.join
    entry = Zip::File.open(path) { it.find_entry("xl/worksheets/sheet1.xml") }

    assert_equal Zlib.crc32(sheet_xml(path)), entry.crc
  end

  def test_an_interrupt_in_close_still_finishes_the_file
    io = GatedIO.new
    writer = Writer.new(io)
    writer.open(nil)
    writer.write({"a" => 1}, ctx)
    io.gate = gate = Gate.new
    interrupted(gate) { writer.close }
    path = File.join(@dir, "interrupted.xlsx")
    File.binwrite(path, io.bytes)

    assert_equal [["a"], [1]], rows(path)
  end

  # Errors

  def test_value_errors_name_the_position_and_the_column
    error = write_error([{"id" => "1"}, {"id" => Time.at(0)}])

    assert_equal 'record at position 2: column "id" is a Time; turn it into a String or a number in a step',
                 error.message
  end

  def test_errors_in_array_records_name_the_column_number
    error = write_error([[1, 10**15]])

    assert_match(/\Arecord at position 1: column 2 has more than 15 digits/, error.message)
  end

  def test_the_row_limit
    with_limit(:MAX_ROWS, 2) do
      error = write_error([{"a" => 1}, {"a" => 2}])

      assert_equal "record at position 2 would be row 3; Excel has 2 rows", error.message
    end
  end

  def test_the_column_limit
    with_limit(:MAX_COLUMNS, 2) do
      assert_equal "record at position 1 has 3 values; Excel has 2 columns", write_error([[1, 2, 3]]).message
    end
  end

  def test_column_model_errors
    error = write_error([{"a" => 1}, {"a" => 2, "b" => 3}])

    assert_match(/\Arecord at position 2 has the key "b", which the first record does not have/, error.message)
  end

  # Targets and batches

  def test_dash_is_stdout
    out, = capture_io do
      writer = Writer.new("-")
      writer.open(nil)
      writer.write({"a" => 1}, ctx)
      writer.close
    end
    path = File.join(@dir, "stdout.xlsx")
    File.binwrite(path, out)

    assert_equal [["a"], [1]], rows(path)
  end

  def test_a_batch_is_written_like_single_records
    path = File.join(@dir, "batch.xlsx")
    writer = Writer.new(path)
    writer.open(nil)
    writer.write_batch([{"a" => 1}, {"a" => 2}], [ctx(1), ctx(2)])
    writer.close

    assert_equal [["a"], [1], [2]], rows(path)
  end

end
