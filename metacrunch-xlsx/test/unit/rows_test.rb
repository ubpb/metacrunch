# frozen_string_literal: true

require "test_helper"

class RowsTest < Minitest::Test

  SHEET = "xl/worksheets/sheet1.xml"

  def test_values_by_type
    data = row(1, cell("A1", "0", type: "s"), %(<c r="B1" t="inlineStr"><is><t>in&amp;line</t></is></c>),
               cell("C1", "s&lt;tr", type: "str"), cell("D1", "42"), cell("E1", "-1.5"), cell("F1", "1E+3"),
               cell("G1", "2.0"), cell("H1", "0.30000000000000004"), cell("I1", "1", type: "b"),
               cell("J1", "0", type: "b"), cell("K1", "#N/A", type: "e"), cell("L1", "2024-11-01T00:00:00Z", type: "d"),
               cell("M1", "12345678901234567890"), cell("N1", "1E+20"))

    assert_equal [[1, ["shared", "in&line", "s<tr", 42, -1.5, 1000, 2, 0.30000000000000004, true, false, "#N/A",
                       "2024-11-01", 12_345_678_901_234_567_890, 1.0e20], nil]],
                 rows(data, strings: ["<t>shared</t>"])
  end

  def test_line_breaks_in_formula_strings_are_normalized
    assert_equal [[1, ["a\nb"], nil]], rows(row(1, cell("A1", "a\r\nb", type: "str")))
  end

  def test_dates_by_format
    data = row(1, cell("A1", "45597", style: 1), cell("B1", "45597.6041666667", style: 2),
               cell("C1", "0.6041666667", style: 3),
               cell("D1", "60", style: 1), cell("E1", "1.5", style: 4), cell("F1", "45597", style: 0),
               cell("G1", "2024-11-01T14:30:00", type: "d"), cell("H1", "2024-11-01T14:30:00", type: "d", style: 1))

    assert_equal [[1, ["2024-11-01", "2024-11-01T14:30:00", "14:30:00", 60, 1.5, 45_597, "2024-11-01T14:30:00",
                       "2024-11-01"], nil]],
                 rows(data, xfs: [0, 14, 22, 21, 46])
  end

  def test_the_1904_system
    assert_equal [[1, ["2028-11-02"], nil]], rows(row(1, cell("A1", "45597", style: 1)), xfs: [0, 14], date1904: true)
  end

  def test_a_number_in_a_text_formatted_cell_stays_a_number
    assert_equal [[1, [9_783_161_484_100], nil]], rows(row(1, cell("A1", "9783161484100", style: 1)), xfs: [0, 49])
  end

  def test_a_formula_without_cached_value_is_nil
    data = row(1, %(<c r="A1"><f>1+1</f></c>), %(<c r="B1"><f>1+1</f><v>2</v></c>))

    assert_equal [[1, [nil, 2], nil]], rows(data)
  end

  # Formulas like =IF(A2="","",A2) store "", often far below a table.
  def test_empty_text_counts_as_no_value
    data = row(1, cell("A1", "a", type: "str"), cell("B1", "", type: "str")) +
           row(2, cell("A2", "", type: "str"), cell("B2", "0", type: "s"), %(<c r="C2" t="inlineStr"><is><t/></is></c>))

    assert_equal [[1, ["a"], nil]], rows(data, strings: ["<t/>"])
  end

  def test_rows_and_cells_without_r_follow_the_previous_one
    data = %(<row><c><v>1</v></c><c><v>2</v></c><c r="E1"><v>5</v></c><c><v>6</v></c></row>) +
           %(<row r="4"><c r="B4"><v>2</v></c></row><row><c><v>1</v></c></row>)

    assert_equal [[1, [1, 2, nil, nil, 5, 6], nil], [4, [nil, 2], nil], [5, [1], nil]], rows(data)
  end

  def test_style_only_cells_and_rows_make_no_value
    data = "#{row(1, cell("A1", "1"), %(<c r="B1" s="0"/>))}#{row(2, %(<c r="A2" s="0"/>))}<row r=\"3\"/>"

    assert_equal [[1, [1], nil]], rows(data)
  end

  def test_prefixed_elements
    data = %(<x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c><x:c r="B1"><x:v>2</x:v></x:c></x:row>)

    assert_equal [[1, ["a", 2], nil]], rows(data, strings: ["<t>a</t>"])
  end

  def test_defective_cells
    defects = {
      cell("B1", "5", type: "s") => "cell B1: shared string 5, the table has 1",
      cell("B1", "abc") => %(cell B1: number "abc"),
      cell("B1", "NaN") => %(cell B1: number "NaN"),
      cell("B1", "2", type: "b") => %(cell B1: boolean "2"),
      cell("B1", "1", type: "z") => %(cell B1: type "z"),
      cell("B1", "1", style: 9) => "cell B1: format 9, the styles have 1",
      cell("B1", "yesterday", type: "d") => %(cell B1: date "yesterday")
    }

    defects.each do |xml, message|
      values, defect = rows(row(1, cell("A1", "1"), xml), strings: ["<t>a</t>"]).first.drop(1)

      assert_equal [1, xml], values, message
      assert_equal message, defect, message
    end
  end

  def test_broken_rows_and_cells
    {row(2, cell("A2", "1")) + row(1, cell("A1", "1")) => "row 1 after row 2",
     row(1, cell("B1", "1"), cell("A1", "1")) => "cell A1 after B1",
     row(1_048_577, cell("A1048577", "1")) => "row 1048577 beyond Excel's last row",
     row(1, cell("XFE1", "1")) => "cell XFE1 beyond Excel's last column",
     row(1, cell("11", "1")) => %(cell reference "11")}.each do |data, reason|
      error = assert_raises(Metacrunch::InputError) { rows(data) }

      assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: #{reason})", error.message
    end
  end

  private

  # [number, values, defect message] of the rows of the first sheet.
  def rows(data, **)
    zip = Metacrunch::Input::Zip.new(StringIO.new(WorkbookBuilder.build(sheets: {"Sheet1" => data}, **)), "a.xlsx")
    workbook = Metacrunch::Xlsx::Workbook.new(zip, "a.xlsx")
    rows = Metacrunch::Xlsx::Rows.new(workbook, workbook.sheet(1), "a.xlsx")
    rows.enum_for(:each).map do |number, values, defect|
      [number, values, defect&.message]
    end
  end

  def row(number, *cells) = %(<row r="#{number}">#{cells.join}</row>)

  def cell(ref, value, type: nil, style: nil)
    %(<c r="#{ref}"#{%( t="#{type}") if type}#{%( s="#{style}") if style}><v>#{value}</v></c>)
  end

end
