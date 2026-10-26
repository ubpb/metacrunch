# frozen_string_literal: true

require "test_helper"

class PackageTest < Minitest::Test

  Package = Metacrunch::Xlsx::Package

  def test_the_static_parts
    assert_equal ["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/styles.xml"],
                 Package::STATIC.keys
  end

  def test_the_static_parts_are_xml
    Package::STATIC.each_value { |xml| assert_instance_of REXML::Document, REXML::Document.new(xml) }
  end

  def test_the_second_cell_format_is_bold
    styles = REXML::Document.new(Package::STATIC.fetch("xl/styles.xml"))
    font = REXML::XPath.first(styles, "//cellXfs/xf[2]/@fontId").value

    assert_equal ["b"], REXML::XPath.match(styles, "//fonts/font[#{Integer(font) + 1}]/b").map(&:name)
  end

  def test_the_workbook_names_the_autofilter
    xml = Package.workbook("Books", "$A$1:$C$3")

    assert_includes xml, '<sheet name="Books" sheetId="1" r:id="rId1"/>'
    assert_includes xml, %(<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'Books'!$A$1:$C$3<)
  end

  def test_quotes_and_ampersands_in_the_sheet_name
    xml = REXML::Document.new(Package.workbook("Tom's & Jerry's", "$A$1:$A$1"))

    assert_equal "Tom's & Jerry's", REXML::XPath.first(xml, "//sheet/@name").value
    assert_equal "'Tom''s & Jerry''s'!$A$1:$A$1", REXML::XPath.first(xml, "//definedName").text
  end

  def test_without_autofilter_no_defined_names
    refute_includes Package.workbook("Books", nil), "definedNames"
  end

end
