# frozen_string_literal: true

require "test_helper"

class RecordTest < Minitest::Test

  Record = Metacrunch::Marcxml::Record
  ControlField = Metacrunch::Marcxml::ControlField
  DataField = Metacrunch::Marcxml::DataField

  def sample
    Record.new(
      leader: "00000nam a2200000 c 4500",
      type: "Bibliographic",
      fields: [
        ControlField.new("001", "123"),
        ControlField.new("008", "#{"x" * 35}ger d"),
        DataField.new("100", "1", " ", [["a", "Doe, Jane"], ["4", "aut"]]),
        DataField.new("245", "1", "0", [["a", "Title"], ["b", "Subtitle"]]),
        DataField.new("650", " ", "7", [["a", "Metadata"], ["2", "gnd"]]),
        DataField.new("650", " ", "4", [["a", "Libraries"]]),
        DataField.new("700", "1", " ", [["a", "Roe, Richard"]]),
        DataField.new("852H", "8", " ", [["b", "MAIN"], ["as", "available"]]),
        DataField.new("856", "4", "0", [["u", "https://example.org/1"]]),
        DataField.new("856", "4", "2", [["u", "https://example.org/2"], ["z", "Cover"]])
      ]
    )
  end

  def tags(fields) = fields.map(&:tag)

  def test_defaults
    record = Record.new

    assert_nil record.leader
    assert_nil record.type
    assert_empty record.fields
  end

  def test_rejects_objects_that_are_not_fields
    error = assert_raises(ArgumentError) { Record.new(fields: ["001"]) }

    assert_match(/a field must be a ControlField or a DataField/, error.message)
  end

  def test_fields_without_arguments_is_the_records_own_array
    record = sample
    record.fields << ControlField.new("009", "x")

    assert_equal "009", record.fields.last.tag
  end

  def test_fields_by_tag
    assert_equal ["650", "650"], tags(sample.fields("650"))
    assert_equal ["100", "700"], tags(sample.fields("700", "100"))
    assert_equal ["100", "700"], tags(sample.fields(["100", "700"]))
  end

  def test_fields_by_range_and_regexp
    assert_equal ["650", "650"], tags(sample.fields("600".."699"))
    assert_equal ["852H", "856", "856"], tags(sample.fields(/\A85/))
  end

  def test_fields_with_four_character_tags
    assert_equal ["852H"], tags(sample.fields("852H"))
  end

  def test_fields_by_indicators
    assert_equal(["https://example.org/2"], sample.fields("856", ind2: "2").map { it["u"] })
    assert_equal 2, sample.fields("856", ind1: "4", ind2: ["0", "2"]).size
    assert_equal ["650"], tags(sample.fields(ind2: "7"))
  end

  def test_indicator_filters_never_match_control_fields
    assert_empty sample.fields("001", ind1: " ")
  end

  def test_rejects_invalid_tag_matchers
    assert_raises(ArgumentError) { sample.fields(245) }
    assert_raises(ArgumentError) { sample.fields(600..699) }
  end

  def test_rejects_invalid_indicator_filters
    assert_raises(ArgumentError) { sample.fields("856", ind1: :blank) }
  end

  def test_field_is_the_first_match
    assert_equal "Metadata", sample.field("650")["a"]
    assert_nil sample.field("999")
  end

  def test_brackets_find_a_field_by_tag
    assert_equal "123", sample["001"].value
    assert_equal "ger", sample["008"][35..37]
  end

  def test_values_of_data_fields
    assert_equal ["Title", "Subtitle"], sample.values("245")
    assert_equal ["Metadata"], sample.values("650", "a", ind2: "7")
    assert_equal ["Doe, Jane", "Roe, Richard"], sample.values(["100", "700"], "a")
  end

  def test_values_of_control_fields_only_without_codes
    assert_equal ["123"], sample.values("001")
    assert_empty sample.values("001", "a")
  end

  def test_value_is_the_first_value
    assert_equal "Subtitle", sample.value("245", "b")
    assert_equal "available", sample.value("852H", "as")
    assert_nil sample.value("999")
  end

  def test_add_inserts_by_tag
    record = sample
    record.add(DataField.new("500", " ", " ", [["a", "Note"]]))
    record.add(ControlField.new("003", "DE-1"))

    assert_equal ["001", "003", "008", "100", "245", "500", "650"], tags(record.fields).first(7)
  end

  def test_add_appends_a_tag_that_sorts_last
    record = sample
    result = record.add(DataField.new("999"))

    assert_same record, result
    assert_equal "999", record.fields.last.tag
  end

  def test_append_adds_at_the_end
    record = sample
    result = record.append(ControlField.new("005", "x"))

    assert_same record, result
    assert_equal "005", record.fields.last.tag
  end

  def test_add_and_append_reject_other_objects
    assert_raises(ArgumentError) { sample.add("500") }
    assert_raises(ArgumentError) { sample.append(nil) }
  end

  def test_remove_returns_the_removed_fields
    record = sample
    removed = record.remove("856", ind2: "2")

    assert_equal(["https://example.org/2"], removed.map { it["u"] })
    assert_equal ["https://example.org/1"], record.values("856", "u")
  end

  def test_remove_without_arguments_removes_all_fields
    record = sample
    record.remove

    assert_empty record.fields
  end

  def test_equality
    assert_equal sample, sample
    assert_equal sample.hash, sample.hash
    refute_equal sample, Record.new(leader: sample.leader, fields: sample.fields)
  end

  def test_dup_is_deep
    original = sample
    copy = original.dup
    copy.fields.first.value << "4"
    copy.field("245").add("c", "x")
    copy.leader << "!"

    assert_equal "123", original["001"].value
    assert_equal ["a", "b"], original["245"].subfields.map(&:code)
    assert_equal "00000nam a2200000 c 4500", original.leader
  end

  def test_dup_and_text_form_without_a_leader
    record = Record.new(fields: [ControlField.new("001", "1")])

    assert_equal record, record.dup
    assert_equal "=001  1", record.to_s
  end

  def test_to_h_is_marc_in_json
    fields = [ControlField.new("001", "1"), DataField.new("245", "1", "0", [["a", "T"]])]
    record = Record.new(leader: "L", fields:)
    expected = {
      "leader" => "L",
      "fields" => [{"001" => "1"}, {"245" => {"ind1" => "1", "ind2" => "0", "subfields" => [{"a" => "T"}]}}]
    }

    assert_equal expected, record.to_h
  end

  def test_to_h_without_a_leader
    assert_equal({"fields" => []}, Record.new.to_h)
  end

  def test_text_form
    fields = [ControlField.new("001", "1"), DataField.new("245", "1", " ", [["a", "T"]])]
    record = Record.new(leader: "L", fields:)

    assert_equal "=LDR  L\n=001  1\n=245  1\\$aT", record.to_s
    assert_equal "#<Metacrunch::Marcxml::Record\n=LDR  L\n=001  1\n=245  1\\$aT>", record.inspect
  end

end
