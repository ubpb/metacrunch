# frozen_string_literal: true

require "test_helper"

class SheetTest < Minitest::Test

  include Helpers

  Sheet = Metacrunch::Xlsx::Sheet

  def setup
    @xml = +""
    @sheet = Sheet.new(@xml)
  end

  def test_a_header_is_bold_and_frozen
    @sheet.start(["id", "title"], nil)

    assert_includes @xml, '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
    assert_includes @xml, '<sheetData><row r="1"><c r="A1" s="1" t="inlineStr"><is><t>id</t></is></c>'
    assert_equal 1, @sheet.rows
  end

  def test_without_header_no_pane
    @sheet.start(nil, nil)

    assert_equal "#{Sheet::HEAD}<sheetData>", @xml
    assert_predicate @sheet, :started?
  end

  def test_an_empty_header_is_no_header
    @sheet.start([], nil)

    refute_includes @xml, "<pane"
    assert_equal 0, @sheet.rows
  end

  def test_widths_come_before_the_rows
    @sheet.start(["id", "title"], [nil, 60])

    assert_includes @xml, '<cols><col min="2" max="2" width="60" customWidth="1"/></cols><sheetData>'
  end

  def test_rows_are_numbered
    @sheet.start(["id"], nil)
    @sheet.row(["1"])
    @sheet.row([nil, 2])

    assert_includes @xml, '<row r="3"><c r="B3"><v>2</v></c></row>'
  end

  def test_a_row_that_cannot_be_written_writes_nothing
    @sheet.start(nil, nil)
    error = assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.row(["a", Time.at(0)]) }

    assert_equal 1, error.index
    assert_equal ["#{Sheet::HEAD}<sheetData>", 0], [@xml, @sheet.rows]
  end

  def test_a_header_that_cannot_be_written_writes_nothing
    assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.start(["a\u0001"], nil) }
    assert_empty @xml
    refute_predicate @sheet, :started?
  end

  def test_the_autofilter_covers_the_header_and_all_rows
    @sheet.start(["id", "title"], nil)
    2.times { @sheet.row(["1", "x", "wide"]) }
    @sheet.finish

    assert @xml.end_with?('</sheetData><autoFilter ref="A1:C3"/></worksheet>')
    assert_equal "$A$1:$C$3", @sheet.absolute_range
  end

  def test_without_header_no_autofilter
    @sheet.start(nil, nil)
    @sheet.row(["1"])
    @sheet.finish

    assert @xml.end_with?("</row></sheetData></worksheet>")
    assert_nil @sheet.absolute_range
  end

  def test_the_row_limit
    with_limit(:MAX_ROWS, 2) do
      @sheet.start(["id"], nil)
      @sheet.row(["1"])
      error = assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.row(["2"]) }

      assert_equal "would be row 3; Excel has 2 rows", error.message
    end
  end

  def test_the_column_limit
    with_limit(:MAX_COLUMNS, 2) do
      @sheet.start(nil, nil)
      error = assert_raises(Metacrunch::Xlsx::Cells::Unwritable) { @sheet.row([1, 2, 3]) }

      assert_equal "has 3 values; Excel has 2 columns", error.message
      assert_nil error.index
    end
  end

end
