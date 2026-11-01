# frozen_string_literal: true

require "test_helper"

class WorkbookTest < Minitest::Test

  Workbook = Metacrunch::Xlsx::Workbook
  Sheet = Workbook::Sheet

  def test_sheets_in_workbook_order_with_their_parts
    targets = rels(["rId1", "worksheet", "worksheets/sheet1.xml"], ["rId2", "worksheet", "/xl/worksheets/Daten.xml"],
                   ["rId3", "chartsheet", "../xl/chartsheets/sheet1.xml"])
    workbook = open_workbook(sheets: {"Tabelle1" => "", "Daten" => "", "Chart1" => ""},
                             extra: {"xl/_rels/workbook.xml.rels" => targets})

    assert_equal [Sheet.new("Tabelle1", "xl/worksheets/sheet1.xml", :worksheet),
                  Sheet.new("Daten", "xl/worksheets/Daten.xml", :worksheet),
                  Sheet.new("Chart1", "xl/chartsheets/sheet1.xml", :chartsheet)], workbook.sheets
  end

  def test_the_workbook_part_is_found_through_the_root_relationships
    parts = {"_rels/.rels" => rels(["rId1", "officeDocument", "/book/main.xml"]),
             "xl/workbook.xml" => nil, "xl/_rels/workbook.xml.rels" => nil,
             "book/main.xml" => WorkbookBuilder.workbook(["Sheet1"], false),
             "book/_rels/main.xml.rels" => rels(["rId1", "worksheet", "../xl/worksheets/sheet1.xml"])}

    assert_equal [Sheet.new("Sheet1", "xl/worksheets/sheet1.xml", :worksheet)], open_workbook(extra: parts).sheets
  end

  def test_strict_ooxml_relationship_types
    workbook = open_workbook(types: WorkbookBuilder::STRICT, strings: ["<t>a</t>"], xfs: [14])

    assert_equal ["Sheet1"], workbook.sheets.map(&:name)
    assert_equal ["a"], workbook.shared_strings
    assert_equal [:date], workbook.kinds
  end

  def test_sheet_by_name_and_by_position
    workbook = open_workbook(sheets: {"Tabelle1" => "", "Daten" => ""})

    assert_equal "Daten", workbook.sheet("Daten").name
    assert_equal "Daten", workbook.sheet(2).name
  end

  def test_a_missing_sheet_names_the_sheets_there_are
    workbook = open_workbook(sheets: {"Tabelle1" => "", "Daten" => ""})

    assert_equal(%(a.xlsx: has no sheet "Bestand"; its sheets: "Tabelle1", "Daten"), error do
      workbook.sheet("Bestand")
    end)
    assert_equal("a.xlsx: has no sheet 3; it has 2", error { workbook.sheet(3) })
  end

  def test_a_chart_sheet_is_refused
    workbook = open_workbook(sheets: {"Chart1" => ""},
                             extra: {"xl/_rels/workbook.xml.rels" => rels(["rId1", "chartsheet", "chartsheets/a.xml"])})

    assert_equal(%(a.xlsx: sheet "Chart1" is a chart sheet), error { workbook.sheet(1) })
  end

  # Only cellXfs counts: not cellStyleXfs, not the numFmt of a dxf.
  def test_kinds_from_built_in_and_custom_formats
    workbook = open_workbook(xfs: [0, 14, 164, 165], formats: {164 => "yyyy-mm-dd hh:mm"})

    assert_equal [:number, :date, :date_time, :number], workbook.kinds
  end

  def test_no_styles_part_is_general
    assert_equal [:number], open_workbook.kinds
  end

  def test_date1904
    assert_predicate open_workbook(date1904: true), :date1904?
    assert_predicate open_workbook(date1904: "true"), :date1904?
    refute_predicate open_workbook(date1904: "false"), :date1904?
  end

  def test_shared_strings_with_rich_text
    workbook = open_workbook(strings: ["<t>Moby</t>", "<r><t>Em</t></r><r><t>ma</t></r>", "<t/>"])

    assert_equal ["Moby", "Emma", ""], workbook.shared_strings
    assert_empty open_workbook.shared_strings
  end

  def test_an_ods_an_xlsb_and_a_zip_without_workbook_are_refused
    ods = WorkbookBuilder.zip("mimetype" => "application/vnd.oasis.opendocument.spreadsheet")
    xlsb = WorkbookBuilder.build(extra: {"_rels/.rels" => rels(["rId1", "officeDocument", "xl/workbook.bin"])})

    assert_equal "a.xlsx: is an OpenDocument spreadsheet (.ods), which metacrunch cannot read; save it as .xlsx first",
                 refusal(ods)
    assert_equal "a.xlsx: is a binary workbook (.xlsb), which metacrunch cannot read; save it as .xlsx first",
                 refusal(xlsb)
    assert_equal "a.xlsx: is a zip archive, but no XLSX workbook", refusal(WorkbookBuilder.zip("a.csv" => "1"))
  end

  def test_a_word_document_is_no_workbook
    parts = {"_rels/.rels" => rels(["rId1", "officeDocument", "word/document.xml"]),
             "word/document.xml" => "<w:document><w:body/></w:document>"}

    assert_equal "a.xlsx: is a zip archive, but no XLSX workbook", refusal(WorkbookBuilder.zip(parts))
  end

  def test_a_part_the_workbook_names_but_the_archive_lacks_is_a_broken_workbook
    workbook = open_workbook(extra: {"xl/worksheets/sheet1.xml" => nil})

    assert_equal("a.xlsx: broken XLSX workbook (xl/worksheets/sheet1.xml: named by the workbook, but missing)",
                 error { workbook.stream("xl/worksheets/sheet1.xml") })
  end

  # Some writers differ in case from the names they give.
  def test_parts_are_found_also_in_another_case
    workbook = open_workbook(extra: {"xl/worksheets/sheet1.xml" => nil,
                                     "xl/Worksheets/Sheet1.xml" => WorkbookBuilder.sheet("")})

    assert_equal "<?xml", workbook.stream("xl/worksheets/sheet1.xml").read(5)
  end

  private

  def open_workbook(**)
    Workbook.new(Metacrunch::Input::Zip.new(StringIO.new(WorkbookBuilder.build(**)), "a.xlsx"), "a.xlsx")
  end

  # Relationships of [id, type, target] in the Transitional namespace.
  def rels(*list)
    WorkbookBuilder.relationships(list.map do |id, type, target|
      WorkbookBuilder.relationship(id, "#{WorkbookBuilder::RELATIONSHIPS}/#{type}", target)
    end)
  end

  def error(&) = assert_raises(Metacrunch::InputError, &).message

  def refusal(bytes)
    zip = Metacrunch::Input::Zip.new(StringIO.new(bytes), "a.xlsx")
    error { Workbook.new(zip, "a.xlsx") }
  end

end
