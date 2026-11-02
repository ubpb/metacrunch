# frozen_string_literal: true

require "test_helper"

class XmlTest < Minitest::Test

  Xml = Metacrunch::Xlsx::Xml
  SHEET = "xl/worksheets/sheet1.xml"

  def test_each_element_yields_rows_across_block_boundaries
    xml = [%(<?xml version="1.0" encoding="UTF-8"?><worksheet><sheetData>),
           %(<row r="1"><c r="A1" t="inlineStr"><is><t>Moby &amp; Dick</t></is></c></row>),
           %(<row r="2" spans="1:1"><c r="A2"><v>2</v></c></row></sheetData></worksheet>)].join

    assert_equal elements(xml, "row"), elements(xml, "row", block: 7)
    assert_equal [%(<row r="2" spans="1:1"><c r="A2"><v>2</v></c></row>)], elements(xml, "row").drop(1)
  end

  # The content of an element that a block does not finish is held apart
  # from the buffer and put back when its end tag comes.
  def test_an_element_longer_than_a_block_comes_whole
    row = %(<x:row r="1">#{"<x:c><x:v>1</x:v></x:c>" * 100}</x:row>)
    xml = %(<x:sheetData><x:row r="0"/>#{row}<x:row r="2"/></x:sheetData>)

    [7, 300, 65_536].each do |block|
      assert_equal [%(<x:row r="0"/>), row, %(<x:row r="2"/>)], elements(xml, "row", block:)
    end
  end

  def test_prefixed_elements_are_found
    xml = %(<x:worksheet xmlns:x="ns"><x:sheetData><x:row r="1"><x:c r="A1"/></x:row></x:sheetData></x:worksheet>)

    assert_equal [%(<x:row r="1"><x:c r="A1"/></x:row>)], elements(xml, "row")
  end

  def test_a_self_closing_element_and_a_longer_name_that_starts_alike
    xml = %(<sheetData><rows/><row r="2"/><row r="3">x</row></sheetData>)

    assert_equal [%(<row r="2"/>), %(<row r="3">x</row>)], elements(xml, "row", block: 3)
  end

  def test_a_greater_than_sign_in_an_attribute_does_not_end_the_tag
    xml = %(<sheetData><row r="1" x="a>b"><c/></row></sheetData>)

    assert_equal [%(<row r="1" x="a>b"><c/></row>)], elements(xml, "row")
  end

  def test_doctype_is_refused
    error = broken(%(<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "b">]><worksheet/>))

    assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: has a DOCTYPE)", error.message
  end

  # A source may hand out fewer bytes than the prolog has.
  def test_the_prolog_is_checked_also_in_small_blocks
    error = assert_raises(Metacrunch::InputError) do
      elements(%(<?xml version="1.0" encoding="UTF-16"?><worksheet/>), "row", block: 7)
    end

    assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: encoding UTF-16)", error.message
  end

  def test_an_encoding_other_than_utf8_is_refused
    error = broken(%(<?xml version="1.0" encoding="UTF-16"?><worksheet/>))

    assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: encoding UTF-16)", error.message
    assert_empty elements(%(<?xml version="1.0" encoding="utf-8"?><worksheet/>), "row")
  end

  # UTF-16 parts, with or without a byte order mark, are refused, not read
  # as no rows; a UTF-8 byte order mark is allowed.
  def test_utf16_parts_are_refused_and_a_utf8_bom_is_allowed
    ["\xFF\xFE<\0r\0o\0w\0/\0>\0", "\xFE\xFF\0<\0r\0o\0w\0/\0>", "<\0r\0o\0w\0/\0>\0"].each do |xml|
      assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: encoding UTF-16)", broken(xml.b).message
    end
    assert_equal ["<row/>"], elements("\xEF\xBB\xBF<row/>".b, "row")
    assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: has a DOCTYPE)",
                 broken("\xEF\xBB\xBF<!DOCTYPE x><row/>".b).message
  end

  def test_an_unclosed_element_is_refused
    error = broken(%(<sheetData><row r="1"><c r="A1"/>))

    assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: unclosed element row)", error.message
  end

  # A huge element costs time in proportion to its size: eight times the
  # size takes about eight times as long, not 64 times. The ratio holds on
  # slow machines too, where a fixed limit in seconds would not.
  def test_a_huge_element_is_read_in_linear_time
    small, large = [275_000, 2_200_000].map do |cells|
      xml = "<sheetData><row r=\"1\">#{"<c><v>1</v></c>" * cells}</row></sheetData>"
      Array.new(2) { timed { assert_equal 1, elements(xml, "row").size } }.min
    end

    assert_operator large / small, :<, 16
  end

  # A start tag whose quote is never closed is given up after a limit.
  def test_an_unclosed_start_tag_is_refused_in_linear_time
    xml = "<sheetData><row r=\"1\" x=\"#{"a>" * 8_000_000}"
    seconds = timed { broken(xml) }

    assert_operator seconds, :<, 2
  end

  def test_invalid_utf8_is_refused
    error = broken("<row>\xFF</row>".b)

    assert_equal "a.xlsx: broken XLSX workbook (#{SHEET}: not valid UTF-8)", error.message
  end

  def test_attributes_drop_prefixes_and_namespace_declarations_and_unescape
    tag = %(<x:row r="A1" t='s' x14ac:dyDescent="0.25" xmlns:r="ns" xmlns="ns" v="&lt;&amp;&#65;"><c/></x:row>)

    assert_equal({"r" => "A1", "t" => "s", "dyDescent" => "0.25", "v" => "<&A"}, Xml.attributes(tag))
  end

  def test_text_joins_rich_runs_and_skips_phonetic_runs
    xml = "<si><r><rPr><b/></rPr><t>Mo</t></r><r><t>by</t></r><rPh sb=\"0\" eb=\"1\"><t>x</t></rPh><tab/></si>"

    assert_equal "Moby", Xml.text(xml)
    assert_equal "", Xml.text("<is><t/></is>")
    assert_equal "a", Xml.text("<x:is><x:t>a</x:t></x:is>")
  end

  def test_text_keeps_space_and_line_breaks
    assert_equal " a\nb ", Xml.text(%(<is><t xml:space="preserve"> a\nb </t></is>))
  end

  def test_text_decodes_entities_and_character_codes
    xml = "<si><t>&amp;&#38;&#x41;&apos;&quot;&gt;_x000D__x005F_x0041_&#xD800;&#1114112;&bogus;</t></si>"

    assert_equal "&&A'\">\r_x0041_&#xD800;&#1114112;&bogus;", Xml.text(xml)
  end

  # XML reads a line break in the text as "\n"; a carriage return that is
  # meant comes as a reference or as Excel's code.
  def test_line_breaks_are_normalized_as_xml_does
    assert_equal "a\nb\nc\rd\re", Xml.text("<is><t>a\r\nb\rc&#13;d_x000D_e</t></is>")
    assert_equal "a\nb", Xml.content("a\r\nb")
  end

  # A CDATA section is text as it stands, without references.
  def test_cdata_is_text
    assert_equal "a<b & c", Xml.text("<is><t><![CDATA[a<b & c]]></t></is>")
    assert_equal "x<&amp;>&\n", Xml.content("x<![CDATA[<&amp;>]]>&amp;\r\n")
  end

  def test_character_codes_of_a_surrogate_pair_are_one_character
    assert_equal "\u{1F600}", Xml.text("<is><t>_xD83D__xDE00_</t></is>")
    assert_equal "�", Xml.text("<is><t>_xD83D_</t></is>")
  end

  def test_text_is_utf8
    assert_equal Encoding::UTF_8, Xml.text("<is><t>é</t></is>".b).encoding
  end

  private

  def elements(xml, local_name, **)
    result = []
    Xml.each_element(StringIO.new(xml.b), local_name, part: SHEET, name: "a.xlsx", **) { result << it }
    result
  end

  def broken(xml) = assert_raises(Metacrunch::InputError) { elements(xml, "row") }

  def timed
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end

end
