# frozen_string_literal: true

require "test_helper"

class EachXmlTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml

  # Gives the input one byte per call, to cut every tag.
  class Trickle

    def initialize(string)
      @bytes = string.b
      @position = 0
    end

    def readpartial(_length)
      raise EOFError if @position >= @bytes.bytesize

      @position += 1
      @bytes.byteslice(@position - 1, 1)
    end

  end

  # Has only read, as some IO-like objects do.
  class ReadOnly

    def initialize(string)
      @io = StringIO.new(string)
    end

    def read(length) = @io.read(length)

  end

  def test_cuts_a_collection_into_records
    xmls = Marcxml.each_xml(fixture("collection.xml")).to_a

    assert_equal 3, xmls.size
    assert(xmls.all? { it.start_with?("<record") && it.end_with?("</record>") })
    assert_equal(Marcxml.each(fixture("collection.xml")).to_a, xmls.map { Marcxml.parse(it) })
  end

  def test_a_bare_record
    xml = %(<record><controlfield tag="001">1</controlfield></record>)

    assert_equal [xml], Marcxml.each_xml(xml).to_a
  end

  def test_prefixed_records
    xmls = Marcxml.each_xml(fixture("prefixed.xml")).to_a

    assert_equal 2, xmls.size
    assert(xmls.all? { it.start_with?("<marc:record>") && it.end_with?("</marc:record>") })
  end

  def test_skips_text_between_records
    xml = %(<?xml version="1.0"?>\n<collection>\n<!-- one -->\n<record>1</record>\n\n) +
          %(<record>2</record>\n</collection>\n)

    assert_equal ["<record>1</record>", "<record>2</record>"], Marcxml.each_xml(xml).to_a
  end

  def test_input_without_records
    assert_empty Marcxml.each_xml("").to_a
    assert_empty Marcxml.each_xml("<collection/>").to_a
  end

  def test_elements_that_only_start_with_record_are_not_records
    assert_equal ["<record>x</record>"], Marcxml.each_xml("<records><record>x</record></records>").to_a
  end

  def test_empty_and_self_closing_records
    xml = "<collection><record/><record></record><record>x</record></collection>"

    assert_equal ["<record/>", "<record></record>", "<record>x</record>"], Marcxml.each_xml(xml).to_a
  end

  def test_records_cut_by_chunk_boundaries
    xml = fixture("collection.xml")

    assert_equal Marcxml.each_xml(xml).to_a, Marcxml.each_xml(Trickle.new(xml)).to_a
  end

  def test_records_are_utf8
    xml = Marcxml.each_xml(Trickle.new("<record>Müller</record>")).first

    assert_equal Encoding::UTF_8, xml.encoding
    assert_equal "<record>Müller</record>", xml
  end

  def test_reads_inputs_with_only_read
    assert_equal 3, Marcxml.each_xml(ReadOnly.new(fixture("collection.xml"))).count
  end

  def test_concatenated_documents_and_bare_records
    assert_equal 6, Marcxml.each_xml(fixture("collection.xml") * 2).count
    assert_equal 2, Marcxml.each_xml("<record/><record/>").count
  end

  def test_needs_a_string_or_an_io
    assert_raises(ArgumentError) { Marcxml.each_xml(nil) { nil } }
  end

end
