# frozen_string_literal: true

require "test_helper"

class ToIso2709Test < Minitest::Test

  include Iso

  Marc = Metacrunch::Marc
  Iso2709 = Metacrunch::Marc::Iso2709
  Record = Metacrunch::Marc::Record
  ControlField = Metacrunch::Marc::ControlField
  DataField = Metacrunch::Marc::DataField

  def test_writes_iso2709
    iso = Iso2709.parse(book).to_iso2709

    assert_equal book, iso.b
    assert_equal Encoding::UTF_8, iso.encoding
  end

  def test_keeps_the_order_of_fields
    record = Record.new(fields: [ControlField.new("005", "x"), ControlField.new("001", "1")])

    assert_equal ["005", "001"], Iso2709.parse(record.to_iso2709).fields.map(&:tag)
  end

  def test_computes_leader_positions_and_keeps_the_record_leader
    record = Record.new(leader: "12345nam  33xxxxx c 1234", fields: [ControlField.new("001", "1")])

    assert_equal "00040nam a2200037 c 4504", record.to_iso2709.byteslice(0, 24)
    assert_equal "12345nam  33xxxxx c 1234", record.leader
  end

  def test_a_record_without_a_leader
    assert_equal "00040    a2200037   4500", Record.new(fields: [ControlField.new("001", "1")]).to_iso2709[0, 24]
  end

  def test_counts_bytes
    record = Record.new(fields: [DataField.new("245", "1", "0", [["a", "Müller"]]), ControlField.new("001", "1")])
    iso = record.to_iso2709

    assert_equal iso.bytesize.to_s.rjust(5, "0"), iso.byteslice(0, 5)
    assert_equal "245001200000", iso.byteslice(24, 12)
    assert_equal "001000200012", iso.byteslice(36, 12)
  end

  def test_transcodes_values_and_takes_binary_values_as_utf8
    record = Record.new(fields: [ControlField.new("001", "Müller".encode("ISO-8859-1")),
                                 DataField.new("245", " ", " ", [["a", "Müller".b]])])

    assert_equal ["Müller", "Müller"], Iso2709.parse(record.to_iso2709).values(["001", "245"])
  end

  def test_transcodes_tags_indicators_and_codes
    tag, ind1, code = ["245", "1", "a"].map { it.encode("UTF-16LE") }
    field = DataField.new(tag, ind1, " ", [[code, "x"]])
    parsed = Iso2709.parse(Record.new(fields: [field]).to_iso2709)["245"]

    assert_equal ["1", "a", "x"], [parsed.ind1, parsed.subfields.first.code, parsed["a"]]
  end

  def test_refuses_what_iso2709_cannot_hold
    {
      DataField.new("852H", "8", " ", [["b", "MAIN"]]) => "field 852H: an ISO 2709 tag has 3 ASCII characters",
      ControlField.new(nil, "1") => "field : an ISO 2709 tag has 3 ASCII characters",
      DataField.new("852", "88", " ", [["b", "MAIN"]]) =>
        %(field 852: an ISO 2709 indicator is 1 ASCII character, got "88"),
      DataField.new("852", "ä", " ", [["b", "MAIN"]]) =>
        %(field 852: an ISO 2709 indicator is 1 ASCII character, got "ä"),
      DataField.new("852", "8", " ", [["as", "MAIN"]]) =>
        %(field 852 $as: an ISO 2709 subfield code is 1 ASCII character, got "as"),
      DataField.new("852", "8", " ") => "field 852: an ISO 2709 data field needs a subfield; without one it would " \
                                        "be read back as a control field"
    }.each do |field, message|
      error = assert_raises(Marc::SerializeError) { Record.new(fields: [field]).to_iso2709 }

      assert_equal message, error.message
    end
  end

  def test_refuses_a_leader_of_another_length
    error = assert_raises(Marc::SerializeError) { Record.new(leader: "00000nam").to_iso2709 }

    assert_equal %(leader: an ISO 2709 leader has 24 ASCII characters, got "00000nam"), error.message
  end

  def test_values_follow_the_common_rule
    {
      ControlField.new("001", "a\x1Eb") => %(field 001: "\\u001E" cannot be represented in XML 1.0),
      ControlField.new("001", "a\u0001b") => %(field 001: "\\u0001" cannot be represented in XML 1.0),
      ControlField.new("001", "a\uFFFFb") => %(field 001: "\\uFFFF" cannot be represented in XML 1.0),
      DataField.new("245", "\x1F", " ", [["a", "x"]]) => %(field 245: "\\u001F" cannot be represented in XML 1.0),
      DataField.new("245", " ", " ", [["a", "x\xFF".b]]) => %(field 245 $a: invalid UTF-8 "x\\xFF"),
      DataField.new("245", " ", " ", [["a", "x\u0001"]]) => %(field 245 $a: "\\u0001" cannot be represented in XML 1.0),
      ControlField.new("\x0101", "1") => %(field \\x0101: "\\u0001" cannot be represented in XML 1.0)
    }.each do |field, message|
      error = assert_raises(Marc::SerializeError) { Record.new(fields: [field]).to_iso2709 }

      assert_equal message, error.message
    end
  end

  def test_a_field_over_9999_bytes
    error = assert_raises(Marc::SerializeError) { long_field.to_iso2709 }

    assert_equal "field 500 has 10005 bytes, ISO 2709 allows 9999 (oversize: :allow writes it anyway)", error.message
  end

  def test_a_field_over_9999_bytes_with_oversize_allow
    iso = long_field.to_iso2709(oversize: :allow)

    assert_equal "500999900000", iso.byteslice(24, 12)
    assert_equal long_field.fields, Iso2709.parse(iso).fields
  end

  def test_a_record_over_99999_bytes
    error = assert_raises(Marc::SerializeError) { long_record.to_iso2709 }

    assert_equal "the record has 114230 bytes, ISO 2709 allows 99999 (oversize: :allow writes it anyway)",
                 error.message
  end

  def test_a_record_over_99999_bytes_with_oversize_allow
    iso = long_record.to_iso2709(oversize: :allow)

    assert_equal "99999", iso.byteslice(0, 5)
    assert_equal "500950599999", iso.byteslice(24 + (11 * 12), 12)
    assert_equal long_record.fields, Iso2709.parse(iso).fields
  end

  def test_rejects_other_oversize_values
    error = assert_raises(ArgumentError) { Record.new.to_iso2709(oversize: true) }

    assert_equal "oversize must be :error or :allow, got true", error.message
  end

  private

  def long_field = Record.new(fields: [DataField.new("500", " ", " ", [["a", "x" * 10_000]])])

  def long_record = Record.new(fields: Array.new(12) { DataField.new("500", " ", " ", [["a", "x" * 9_500]]) })

end
