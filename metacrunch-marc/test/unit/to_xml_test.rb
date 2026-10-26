# frozen_string_literal: true

require "test_helper"

class ToXmlTest < Minitest::Test

  include Fixtures

  Marc = Metacrunch::Marc
  Record = Metacrunch::Marc::Record
  ControlField = Metacrunch::Marc::ControlField
  DataField = Metacrunch::Marc::DataField

  def sample
    Record.new(leader: "00000nam a2200000 c 4500", type: "Bibliographic",
               fields: [ControlField.new("001", "1"), DataField.new("245", "1", "0", [["a", "Title"], ["b", "Sub"]])])
  end

  def test_writes_marcxml
    expected = <<~XML
      <record xmlns="http://www.loc.gov/MARC21/slim" type="Bibliographic">
        <leader>00000nam a2200000 c 4500</leader>
        <controlfield tag="001">1</controlfield>
        <datafield tag="245" ind1="1" ind2="0">
          <subfield code="a">Title</subfield>
          <subfield code="b">Sub</subfield>
        </datafield>
      </record>
    XML

    assert_equal expected, sample.to_xml
  end

  def test_without_namespace_type_and_leader
    xml = Record.new(fields: [ControlField.new("001", "1")]).to_xml(namespace: false)

    assert_equal %(<record>\n  <controlfield tag="001">1</controlfield>\n</record>\n), xml
  end

  def test_escapes_text
    xml = Record.new(fields: [ControlField.new("001", %(a & b < c > d "e"))]).to_xml

    assert_includes xml, %(>a &amp; b &lt; c &gt; d "e"</controlfield>)
  end

  def test_escapes_attributes
    xml = Record.new(fields: [DataField.new(%(5"0), "&", "<", [["\t", "x"]])]).to_xml

    assert_includes xml, %(<datafield tag="5&quot;0" ind1="&amp;" ind2="&lt;">)
    assert_includes xml, %(<subfield code="&#9;">x</subfield>)
  end

  def test_tabs_and_line_breaks_in_text_are_kept
    record = Record.new(fields: [DataField.new("500", " ", " ", [["a", "a\tb\nc"]])])

    assert_includes record.to_xml, ">a\tb\nc<"
  end

  def test_carriage_returns_survive
    record = Record.new(fields: [DataField.new("500", " ", " ", [["a", "a\r\nb"]])])

    assert_includes record.to_xml, "a&#13;\nb"
    assert_equal record, Marc::Xml.parse(record.to_xml)
  end

  def test_nil_values_are_written_empty
    xml = Record.new(fields: [ControlField.new("001", nil)]).to_xml

    assert_includes xml, %(<controlfield tag="001"></controlfield>)
  end

  def test_rejects_characters_xml_cannot_represent
    ["\u0001", "\u000B", "\u001F", "\uFFFE", "\uFFFF"].each do |char|
      record = Record.new(fields: [DataField.new("245", "1", "0", [["a", "x#{char}y"]])])
      error = assert_raises(Marc::SerializeError) { record.to_xml }

      assert_match(/\Afield 245 \$a: /, error.message)
    end
  end

  def test_rejects_invalid_utf8
    record = Record.new(fields: [ControlField.new("001", "M\xFCller")])
    error = assert_raises(Marc::SerializeError) { record.to_xml }

    assert_match(/\Afield 001: invalid UTF-8/, error.message)
  end

  def test_transcodes_strings_in_other_encodings
    record = Record.new(fields: [ControlField.new("001", "Müller".encode("ISO-8859-1"))])

    assert_equal "Müller", Marc::Xml.parse(record.to_xml)["001"].value
  end

  def test_rejects_strings_that_cannot_be_transcoded
    record = Record.new(fields: [ControlField.new("001", "\x82".dup.force_encoding("Shift_JIS"))])

    assert_raises(Marc::SerializeError) { record.to_xml }
  end

  def test_messages_show_invalid_bytes_as_escapes
    record = Record.new(fields: [DataField.new("245", " ", " ", [["\xE4".b, "\u0001"]])])
    error = assert_raises(Marc::SerializeError) { record.to_xml }

    assert_predicate error.message, :valid_encoding?
    assert_match(/\Afield 245 \$\\xE4: /, error.message)
  end

  def test_round_trip_of_every_fixture
    ["collection.xml", "prefixed.xml", "local.xml", "edge.xml"].each do |name|
      Marc::Xml.each(fixture(name)) do |record|
        assert_equal record, Marc::Xml.parse(record.to_xml), name
      end
    end
  end

  def test_round_trip_of_tricky_values
    record = Record.new(
      leader: "00000nam a2200000 c 4500", type: "Bibliographic",
      fields: [
        ControlField.new("008", "  spaces at both ends  "),
        DataField.new("245", " ", " ", [["a", %(Quotes " and ' and <tags> & more)], ["b", "Ünïcödé"], ["c", ""]]),
        DataField.new("852H", "8", " ", [["as", "line\nbreak\tand tab\r"]])
      ]
    )

    assert_equal record, Marc::Xml.parse(record.to_xml)
  end

end
