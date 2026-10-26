# frozen_string_literal: true

require "test_helper"

class XmlEachRawTest < Minitest::Test

  include Fixtures
  include Inputs

  Marc = Metacrunch::Marc

  def test_cuts_a_collection_into_records
    xmls = Marc::Xml.each_raw(fixture("collection.xml")).to_a

    assert_equal 3, xmls.size
    assert(xmls.all? { it.start_with?("<record") && it.end_with?("</record>") })
    assert_equal(Marc::Xml.each(fixture("collection.xml")).to_a, xmls.map { Marc::Xml.parse(it) })
  end

  def test_a_bare_record
    xml = %(<record><controlfield tag="001">1</controlfield></record>)

    assert_equal [xml], Marc::Xml.each_raw(xml).to_a
  end

  def test_prefixed_records
    xmls = Marc::Xml.each_raw(fixture("prefixed.xml")).to_a

    assert_equal 2, xmls.size
    assert(xmls.all? { it.start_with?("<marc:record>") && it.end_with?("</marc:record>") })
  end

  def test_skips_text_between_records
    xml = %(<?xml version="1.0"?>\n<collection>\n<!-- one -->\n<record>1</record>\n\n) +
          %(<record>2</record>\n</collection>\n)

    assert_equal ["<record>1</record>", "<record>2</record>"], Marc::Xml.each_raw(xml).to_a
  end

  # each raises at a NUL byte; each_raw, and so the Reader, skip it between
  # records.
  def test_skips_nul_bytes_between_records
    xml = "\x00<collection>\x00<record>1</record>\x00<record>2</record></collection>\x00"

    assert_equal ["<record>1</record>", "<record>2</record>"], Marc::Xml.each_raw(xml).to_a
    assert_equal ["<record>1</record>", "<record>2</record>"], Marc::Xml.each_raw(StringIO.new(xml)).to_a
  end

  def test_input_without_records
    assert_empty Marc::Xml.each_raw("").to_a
    assert_empty Marc::Xml.each_raw("<collection/>").to_a
  end

  def test_elements_that_only_start_with_record_are_not_records
    assert_equal ["<record>x</record>"], Marc::Xml.each_raw("<records><record>x</record></records>").to_a
  end

  def test_empty_and_self_closing_records
    xml = "<collection><record/><record></record><record>x</record></collection>"

    assert_equal ["<record/>", "<record></record>", "<record>x</record>"], Marc::Xml.each_raw(xml).to_a
  end

  def test_a_record_cut_off_by_the_end_of_the_input
    xml = %(<collection><record>1</record><record type="x">2</rec)

    assert_equal ["<record>1</record>", %(<record type="x">2</rec)], Marc::Xml.each_raw(xml).to_a
  end

  def test_records_cut_by_chunk_boundaries
    xml = fixture("collection.xml")

    assert_equal Marc::Xml.each_raw(xml).to_a, Marc::Xml.each_raw(Trickle.new(xml)).to_a
  end

  def test_records_are_utf8
    xml = Marc::Xml.each_raw(Trickle.new("<record>Müller</record>")).first

    assert_equal Encoding::UTF_8, xml.encoding
    assert_equal "<record>Müller</record>", xml
  end

  def test_reads_inputs_with_only_read
    assert_equal 3, Marc::Xml.each_raw(ReadOnly.new(fixture("collection.xml"))).count
  end

  def test_concatenated_documents_and_bare_records
    assert_equal 6, Marc::Xml.each_raw(fixture("collection.xml") * 2).count
    assert_equal 2, Marc::Xml.each_raw("<record/><record/>").count
  end

  def test_concatenated_documents_with_different_prefixes
    xml = fixture("collection.xml") + fixture("prefixed.xml") + fixture("local.xml")

    ids = Marc::Xml.each_raw(xml).map { Marc::Xml.parse(it)["001"].value }

    assert_equal ["book-1", "article-1", "holding-1", "prefixed-1", "prefixed-2", "local-1"], ids
  end

  def test_long_input_in_chunks_of_any_size
    records = Array.new(4_000) { %(<record type="Bibliographic"><controlfield tag="001">#{it}</controlfield></record>) }
    xml = "<collection>#{records.join("\n")}</collection>"

    [70_001, 70_013, 70_019, 99_991, 131_071].each do |size|
      assert_equal records, Marc::Xml.each_raw(Chunked.new(xml, size)).to_a, "chunks of #{size}"
    end
  end

  def test_a_large_record_across_many_chunks
    values = Array.new(2_000) { |i| %(<subfield code="a">#{"x" * 100}#{i}</subfield>) }
    xml = %(<record><datafield tag="500">#{values.join}</datafield></record>)

    assert_equal [xml], Marc::Xml.each_raw(xml).to_a
  end

  def test_needs_a_string_or_an_io
    assert_raises(ArgumentError) { Marc::Xml.each_raw(nil) { nil } }
  end

end
