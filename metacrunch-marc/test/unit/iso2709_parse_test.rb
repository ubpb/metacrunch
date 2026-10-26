# frozen_string_literal: true

require "test_helper"

class Iso2709ParseTest < Minitest::Test

  include Iso

  Marc = Metacrunch::Marc
  Iso2709 = Metacrunch::Marc::Iso2709
  MARC8 = "00000nam  2200000 c 4500"

  def test_parses_a_record
    record = Iso2709.parse(book)

    assert_equal "00067nam a2200049 c 4500", record.leader
    assert_equal ["=001  1", "=245  10$aTitle$bSub"], record.fields.map(&:to_s)
    assert_nil record.type
  end

  def test_values_and_tags_are_utf8
    field = Iso2709.parse(raw(["245", "10\x1FaMüller"]))["245"]

    assert_equal "Müller", field["a"]
    assert_equal [Encoding::UTF_8] * 3, [field.tag, field.ind1, field["a"]].map(&:encoding)
  end

  def test_ignores_the_record_length_and_the_base_address
    broken = book
    broken[0, 5] = "00042"
    broken[12, 5] = "00999"

    assert_equal Iso2709.parse(book).fields, Iso2709.parse(broken).fields
    assert_equal "00042nam a2200999 c 4500", Iso2709.parse(broken).leader
  end

  def test_reads_records_with_99999_and_00000_as_their_length
    ["99999", "00000"].each do |length|
      record = book
      record[0, 5] = length

      assert_equal Iso2709.parse(book).fields, Iso2709.parse(record).fields
    end
  end

  # After a conversion from MARC-8, lengths and starts may count characters.
  def test_ignores_lengths_and_starts_counted_in_characters
    record = raw(["001", "1"], ["245", "10\x1FaMüller"], ["500", "  \x1Fax"])
    record[24 + 12 + 3, 4] = "0011"
    record[24 + 24 + 7, 5] = "00013"

    assert_equal ["1", "Müller", "x"], Iso2709.parse(record).values(["001", "245", "500"])
  end

  def test_ignores_field_lengths_that_are_not_digits
    record = book
    record[24 + 3, 4] = "\xFF\x01ab".b

    assert_equal Iso2709.parse(book).fields, Iso2709.parse(record).fields
  end

  def test_starts_must_not_decrease
    record = book
    record[24 + 7, 5] = "00005"
    error = assert_raises(Marc::ParseError) { Iso2709.parse(record) }

    assert_equal "directory entry 2 (245): the start 2 is less than the start before it (5)", error.message
  end

  def test_a_start_must_be_five_digits
    record = book
    record[24 + 12 + 7, 5] = "0 002"
    error = assert_raises(Marc::ParseError) { Iso2709.parse(record) }

    assert_equal %(directory entry 2 (245): the start "0 002" is not 5 digits), error.message
  end

  def test_more_fields_than_directory_entries
    error = assert_raises(Marc::ParseError) { Iso2709.parse(book.sub("Title", "Ti\x1Etle")) }

    assert_equal "the directory has 2 entries, the data 3 fields", error.message
  end

  def test_fewer_fields_than_directory_entries
    error = assert_raises(Marc::ParseError) { Iso2709.parse(book.sub("1\x1E", "1")) }

    assert_equal "the directory has 2 entries, the data 1 fields", error.message
  end

  def test_the_last_field_terminator_may_be_missing
    assert_equal Iso2709.parse(book).fields, Iso2709.parse(book.sub("\x1E\x1D", "\x1D")).fields
  end

  def test_records_without_fields_and_empty_values
    assert_empty Iso2709.parse(raw).fields
    assert_equal [""], Iso2709.parse(raw(["001", ""])).values("001")
    assert_equal([["a", ""], ["b", "x"]],
                 Iso2709.parse(raw(["245", "10\x1Fa\x1Fbx"]))["245"].subfields.map { [it.code, it.value] })
  end

  def test_a_short_record
    error = assert_raises(Marc::ParseError) { Iso2709.parse("0012\x1D") }

    assert_equal "the record has 5 bytes, fewer than its leader of 24 and the terminator", error.message
  end

  def test_the_leader_must_be_ascii
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["001", "1"], leader: "00000nam a2200000 é 450")) }

    assert_equal %(leader: an ISO 2709 leader has 24 ASCII characters, got "00040nam a2200037 \\xC3\\xA9 450"),
                 error.message
  end

  def test_the_leader_follows_the_common_rule
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["001", "1"], leader: "00000nam a2200000 \x01 4500")) }

    assert_equal %(leader: "\\u0001" cannot be represented in XML 1.0), error.message
  end

  def test_the_directory_needs_its_terminator
    error = assert_raises(Marc::ParseError) { Iso2709.parse("#{LEADER}001\x1D") }

    assert_equal "the directory has no end (no field terminator)", error.message
  end

  def test_the_directory_has_whole_entries
    error = assert_raises(Marc::ParseError) { Iso2709.parse("#{LEADER}001000\x1E\x1D") }

    assert_equal "the directory has 6 bytes, not a multiple of 12", error.message
  end

  def test_tags_must_be_ascii
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["ü5", "1"])) }

    assert_equal %(directory entry 1: the tag "\\xC3\\xBC5" is not 3 ASCII characters), error.message
  end

  def test_tags_follow_the_common_rule
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["\x0145", "1"])) }

    assert_equal %(directory entry 1: the tag "\\u0001" cannot be represented in XML 1.0), error.message
  end

  def test_a_field_with_a_subfield_delimiter_is_a_data_field
    record = Iso2709.parse(raw(["FMT", "BK"], ["001", "  \x1Fax"], ["500", "  "]))

    assert_instance_of Marc::ControlField, record["FMT"]
    assert_instance_of Marc::DataField, record["001"]
    assert_equal "  ", record["500"].value
  end

  def test_a_data_field_has_two_indicators
    {"1" => %(got "1"), "100" => %(got "100")}.each do |indicators, got|
      error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["245", "#{indicators}\x1Fax"])) }

      assert_equal "field 245: ISO 2709 indicators are 2 characters, #{got}", error.message
    end
  end

  def test_indicators_are_characters
    assert_equal "ä", Iso2709.parse(raw(["245", "ä \x1Fax"]))["245"].ind1
  end

  def test_a_subfield_needs_a_code
    [raw(["245", "10\x1F\x1Fax"]), raw(["245", "10\x1Fax\x1F"])].each do |record|
      error = assert_raises(Marc::ParseError) { Iso2709.parse(record) }

      assert_equal "field 245: a subfield without a code", error.message
    end
  end

  def test_a_code_is_one_character
    subfields = Iso2709.parse(raw(["245", "10\x1Fäx\x1Fb"]))["245"].subfields

    assert_equal([["ä", "x"], ["b", ""]], subfields.map { [it.code, it.value] })
  end

  def test_values_follow_the_common_rule
    {
      raw(["245", "10\x1Fax\x01y"]) => %(field 245 $a: "\\u0001" cannot be represented in XML 1.0),
      raw(["001", "x\x1Cy"]) => %(field 001: "\\u001C" cannot be represented in XML 1.0),
      raw(["001", "x\uFFFEy"]) => %(field 001: "\\uFFFE" cannot be represented in XML 1.0),
      raw(["245", "1\x02\x1Fax"]) => %(field 245 indicators: "\\u0002" cannot be represented in XML 1.0),
      raw(["245", "10\x1Fa\x1Dx"]) => %(field 245 $a: "\\u001D" cannot be represented in XML 1.0)
    }.each do |record, message|
      error = assert_raises(Marc::ParseError) { Marc::Iso2709::Parser.parse(record, normalize: nil) }

      assert_equal message, error.message
    end
  end

  def test_invalid_utf8_with_a_marc8_leader_gets_a_hint
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["245", "10\x1FaM\xE8uller"], leader: MARC8)) }

    assert_equal "field 245 $a: invalid UTF-8; leader/09 says MARC-8; convert the file to UTF-8 first, e.g. " \
                 "yaz-marcdump -f MARC-8 -t UTF-8 -o marc -l 9=97 in.mrc > out.mrc", error.message
  end

  # MARC-8 switches to Cyrillic, Greek, Hebrew, Arabic or CJK with ESC
  # sequences over ASCII bytes, so those fields are valid UTF-8.
  def test_marc8_script_escapes_get_the_hint
    record = raw(["880", "10\x1Fa\e(NTOLSTOJ\e(B"], leader: MARC8)
    error = assert_raises(Marc::ParseError) { Iso2709.parse(record) }

    assert_equal %(field 880 $a: "\\e" cannot be represented in XML 1.0; #{Marc::Iso2709::Parser::MARC8}), error.message
  end

  def test_escapes_with_a_utf8_leader_get_no_hint
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["880", "10\x1Fa\e(N"])) }

    assert_equal %(field 880 $a: "\\e" cannot be represented in XML 1.0), error.message
  end

  def test_invalid_utf8_with_a_utf8_leader
    error = assert_raises(Marc::ParseError) { Iso2709.parse(raw(["245", "10\x1FaM\xE8uller"])) }

    assert_equal "field 245 $a: invalid UTF-8", error.message
  end

  def test_marc8_records_in_ascii_are_read
    assert_equal "Muller", Iso2709.parse(raw(["245", "10\x1FaMuller"], leader: MARC8))["245"]["a"]
  end

  def test_normalize
    record = raw(["245", "10\x1FaMu\u0308ller"])

    assert_equal "Müller", Iso2709.parse(record, normalize: :nfc)["245"]["a"]
    assert_equal "Mu\u0308ller", Iso2709.parse(record)["245"]["a"]
  end

  def test_parse_needs_a_record
    assert_equal "no record found", assert_raises(Marc::ParseError) { Iso2709.parse(" \n") }.message
  end

  def test_parse_takes_one_record_only
    error = assert_raises(Marc::ParseError) { Iso2709.parse(book * 2) }

    assert_equal "2 records found where one was expected (use Marc::Iso2709.each)", error.message
  end

  def test_parse_skips_line_breaks_around_the_record
    assert_equal ["1"], Iso2709.parse("\n#{book}\r\n".b).values("001")
  end

  def test_a_record_without_its_terminator
    error = assert_raises(Marc::ParseError) { Iso2709.parse(book.chomp("\x1D")) }

    assert_equal "the input ended inside a record", error.message
  end

  def test_rejects_invalid_arguments
    assert_raises(ArgumentError) { Iso2709.parse(nil) }
    assert_raises(ArgumentError) { Iso2709.parse(book, normalize: :nfd) }
  end

end
