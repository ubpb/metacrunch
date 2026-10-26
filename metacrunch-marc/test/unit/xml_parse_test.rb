# frozen_string_literal: true

require "test_helper"

class XmlParseTest < Minitest::Test

  include Fixtures

  Marc = Metacrunch::Marc
  DataField = Metacrunch::Marc::DataField

  def ids(records) = records.map { it["001"].value }

  def edge = Marc::Xml.parse(fixture("edge.xml"))

  def test_each_yields_every_record_of_a_collection
    records = File.open(fixture_path("collection.xml")) { Marc::Xml.each(it).to_a }

    assert_equal ["book-1", "article-1", "holding-1"], ids(records)
    assert_equal ["Bibliographic", "Bibliographic", "Holdings"], records.map(&:type)
  end

  def test_reads_leader_fields_and_subfields_in_order
    book = Marc::Xml.each(fixture("collection.xml")).first
    title = DataField.new("245", "1", "0", [["a", "Metadata in practice"], ["b", "a handbook"], ["c", "Jane Doe"]])

    assert_equal "00000nam a2200000 c 4500", book.leader
    assert_equal ["001", "008", "020", "100", "245", "264", "650"], book.fields.map(&:tag)
    assert_equal title, book["245"]
  end

  def test_keeps_whitespace_and_line_breaks
    assert_equal ["  Two  spaces  ", "Line one\nline two", "Second a"], edge["245"].values
  end

  def test_keeps_subfield_order_and_repeated_control_fields
    assert_equal ["a", "b", "a"], edge["245"].subfields.map(&:code)
    assert_equal ["cr", "tu"], edge.values("007")
  end

  def test_reads_cdata_comments_entities_and_empty_values
    assert_equal ["Tom & Jerry <3", "splitvalue", "& < > \" é", ""], edge["500"].values
  end

  def test_missing_and_empty_indicators_are_blank
    empty = Marc::Xml.parse(%(<record><datafield tag="500" ind1="" ind2=""/></record>))["500"]

    assert_equal [" ", " "], [edge["500"].ind1, edge["500"].ind2]
    assert_equal [" ", " "], [empty.ind1, empty.ind2]
  end

  def test_prefixed_elements
    records = Marc::Xml.each(fixture("prefixed.xml")).to_a

    assert_equal ["prefixed-1", "prefixed-2"], ids(records)
    assert_equal "First", records.first.value("245", "a")
  end

  def test_leader_after_control_fields_and_local_tags
    record = Marc::Xml.parse(fixture("local.xml"))

    assert_equal "00000nam a2200000 c 4500", record.leader
    assert_equal "available", record.value("852H", "as")
    assert_equal "https://example.org/local-1", record.value("AVA", "dl")
  end

  def test_empty_records
    assert_equal Marc::Record.new, Marc::Xml.parse("<record></record>")
    assert_equal Marc::Record.new, Marc::Xml.parse("<record/>")
  end

  def test_ignores_unknown_elements
    xml = %(<wrapper><record><datafield tag="500"><subfield code="a">x<b>y</b>z</subfield></datafield>) +
          %(</record></wrapper>)

    assert_equal "xz", Marc::Xml.parse(xml).value("500", "a")
  end

  def test_reads_strings_files_stringios_gzip_and_pipes
    xml = fixture("collection.xml")
    expected = Marc::Xml.each(xml).to_a
    reader, writer = IO.pipe
    Thread.new do
      writer.write(xml)
      writer.close
    end
    inputs = [File.open(fixture_path("collection.xml")), StringIO.new(xml),
              Zlib::GzipReader.new(StringIO.new(Zlib.gzip(xml))), reader]

    inputs.each { assert_equal expected, Marc::Xml.each(it).to_a }
  ensure
    inputs&.each(&:close)
  end

  # Ox reads a StringIO's string directly, which is superlinear in its size.
  def test_a_stringio_reaches_ox_through_readpartial
    received = nil
    original = Ox.method(:sax_parse)
    Ox.define_singleton_method(:sax_parse) { |_handler, io, **| received = io }
    Marc::Xml.each(StringIO.new("<record/>")) { nil }

    refute_kind_of StringIO, received
    assert_respond_to received, :readpartial
  ensure
    Ox.define_singleton_method(:sax_parse, original)
  end

  def test_values_are_utf8_without_an_xml_declaration
    value = Marc::Xml.parse(%(<record><controlfield tag="001">Müller</controlfield></record>))["001"].value

    assert_equal Encoding::UTF_8, value.encoding
    assert_equal "Müller", value
  end

  def test_reads_input_with_a_byte_order_mark
    record = Marc::Xml.parse(%(\uFEFF<record><controlfield tag="001">x</controlfield></record>))

    assert_equal "x", record["001"].value
  end

  def test_line_breaks_are_normalized_as_xml_demands
    xml = %(<record><datafield tag="500"><subfield code="a">a\r\nb</subfield></datafield></record>)

    assert_equal "a\nb", Marc::Xml.parse(xml).value("500", "a")
  end

  def test_normalize_nfc
    xml = %(<record><controlfield tag="001">Mu\u0308ller</controlfield></record>)

    assert_equal "Mu\u0308ller", Marc::Xml.parse(xml)["001"].value
    assert_equal "Müller", Marc::Xml.parse(xml, normalize: :nfc)["001"].value
  end

  def test_rejects_unknown_normalizations
    assert_raises(ArgumentError) { Marc::Xml.parse("<record/>", normalize: :nfd) }
  end

  def test_syntax_errors_name_line_and_column
    xml = %(<record>\n<datafield tag="245">\n<subfield code="a">x</datafield>\n</record>)
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_match(/Start End Mismatch/, error.message)
    assert_equal [3, 21], [error.line, error.column]
  end

  def test_input_that_ends_inside_a_record
    assert_raises(Marc::ParseError) { Marc::Xml.parse(%(<record><datafield tag="245"><subfield code="a">x)) }
  end

  def test_invalid_entities
    xml = %(<record><controlfield tag="001">a &foo; b</controlfield></record>)

    assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }
  end

  def test_values_that_are_not_utf8
    xml = "<record><datafield tag=\"245\"><subfield code=\"a\">M\xFCller</subfield></datafield></record>".b
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_equal "field 245 $a: invalid UTF-8", error.message
  end

  def test_a_leader_that_is_not_utf8
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse("<record><leader>\xFF</leader></record>".b) }

    assert_equal "leader: invalid UTF-8", error.message
  end

  def test_a_control_field_that_is_not_utf8
    xml = "<record><controlfield tag=\"001\">\xFF</controlfield></record>".b
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_equal "field 001: invalid UTF-8", error.message
  end

  def test_ignores_elements_outside_their_parent
    xml = %(<collection><datafield tag="1"/><controlfield tag="2">x</controlfield><leader>y</leader>) +
          %(<subfield code="a">z</subfield><record/></collection>)

    assert_equal [Marc::Record.new], Marc::Xml.each(xml).to_a
  end

  def test_a_record_inside_a_record_starts_anew
    xml = %(<record><header/><record><controlfield tag="001">1</controlfield></record></record>)

    assert_equal ["1"], ids(Marc::Xml.each(xml).to_a)
  end

  def test_ignores_unknown_attributes
    xml = %(<record id="r"><controlfield tag="001" x="1">1</controlfield>) +
          %(<datafield tag="245" ind1="1" ind2="0" x="1"><subfield code="a" lang="en">T</subfield></datafield></record>)
    record = Marc::Xml.parse(xml)

    assert_equal "1", record["001"].value
    assert_equal ["1", "0", "T"], [record["245"].ind1, record["245"].ind2, record["245"]["a"]]
  end

  def test_finish_raises_inside_a_record
    parser = Marc::Xml::Parser.new(nil, proc {})
    parser.start_element(:record)

    assert_raises(Marc::ParseError) { parser.finish }
  end

  def test_raw_control_characters_in_values
    xml = "<record><datafield tag=\"500\"><subfield code=\"a\">a\x1Fb</subfield></datafield></record>"
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_equal %(field 500 $a: "\\u001F" cannot be represented in XML 1.0), error.message
  end

  def test_character_references_xml_cannot_represent
    xml = %(<record><controlfield tag="001">a&#31;b</controlfield></record>)

    assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }
  end

  def test_invalid_bytes_in_names
    xml = "<record><datafield tag=\"500\"><subfield c\xF6de=\"a\">x</subfield></datafield></record>".b
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_match(/\Ainvalid UTF-8 in markup/, error.message)
  end

  def test_invalid_utf8_in_attribute_values
    xml = "<record><datafield tag=\"24\xFF\"><subfield code=\"a\">x</subfield></datafield></record>".b
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_equal "invalid UTF-8 in attribute tag", error.message
  end

  def test_characters_xml_cannot_represent_in_attributes
    xml = %(<record><datafield tag="5&#1;0"><subfield code="a">x</subfield></datafield></record>)
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(xml) }

    assert_equal %(attribute tag: "\\u0001" cannot be represented in XML 1.0), error.message
  end

  def test_encoding_errors_of_the_block_are_not_parse_errors
    assert_raises(Encoding::CompatibilityError) do
      Marc::Xml.each("<record/>") { raise Encoding::CompatibilityError, "from the block" }
    end
  end

  def test_bare_records_need_a_collection
    assert_raises(Marc::ParseError) { Marc::Xml.each("<record/><record/>").to_a }
  end

  def test_parse_needs_exactly_one_record
    assert_raises(Marc::ParseError) { Marc::Xml.parse("<collection/>") }
    error = assert_raises(Marc::ParseError) { Marc::Xml.parse(fixture("collection.xml")) }

    assert_match(/3 records found/, error.message)
  end

  def test_parse_needs_a_string
    assert_raises(ArgumentError) { Marc::Xml.parse(StringIO.new("<record/>")) }
  end

  def test_each_without_a_block_is_an_enumerator
    assert_instance_of Enumerator, Marc::Xml.each("<record/>")
  end

  def test_each_needs_a_string_or_an_io
    assert_raises(ArgumentError) { Marc::Xml.each(42) { nil } }
  end

end
