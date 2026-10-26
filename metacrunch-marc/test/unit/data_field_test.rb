# frozen_string_literal: true

require "test_helper"

class DataFieldTest < Minitest::Test

  DataField = Metacrunch::Marc::DataField
  Subfield = Metacrunch::Marc::Subfield

  def title
    DataField.new("245", "1", "0", [["a", "Title"], ["b", "Subtitle"], ["c", "Jane Doe"], ["a", "Second"]])
  end

  def test_indicators_default_to_blank
    field = DataField.new("500")

    assert_equal [" ", " "], [field.ind1, field.ind2]
    assert_empty field.subfields
  end

  def test_nil_indicators_become_blank
    field = DataField.new("500", nil, nil)
    field.ind1 = nil
    field.ind2 = "1"

    assert_equal [" ", "1"], [field.ind1, field.ind2]
  end

  def test_subfields_from_pairs_and_subfields
    field = DataField.new("100", "1", " ", [["a", "Doe, Jane"], Subfield.new("4", "aut")])

    assert_equal [Subfield.new("a", "Doe, Jane"), Subfield.new("4", "aut")], field.subfields
  end

  def test_rejects_other_subfield_values
    error = assert_raises(ArgumentError) { DataField.new("100", " ", " ", [{"a" => "x"}]) }

    assert_match(/a subfield must be a Subfield or a \[code, value\] pair/, error.message)
  end

  def test_subfields_without_codes_is_the_fields_own_array
    field = title
    field.subfields << Subfield.new("x", "added")

    assert_equal "added", field.subfields.last.value
  end

  def test_subfields_with_codes_keep_the_field_order
    assert_equal ["a", "b", "a"], title.subfields("b", "a").map(&:code)
  end

  def test_each_subfield_yields_in_field_order
    codes = []
    title.each_subfield { codes << it.code }

    assert_equal ["a", "b", "c", "a"], codes
  end

  def test_values
    assert_equal ["Title", "Subtitle", "Jane Doe", "Second"], title.values
    assert_equal ["Title", "Second"], title.values("a")
    assert_equal ["Title", "Subtitle", "Second"], title.values("b", "a")
  end

  def test_value_is_the_first_value
    assert_equal "Title", title.value
    assert_equal "Subtitle", title.value("b")
    assert_nil title.value("z")
  end

  def test_brackets_read_the_first_value_of_a_code
    assert_equal "Jane Doe", title["c"]
  end

  def test_join
    assert_equal "Title : Subtitle : Second", title.join("a", "b", separator: " : ")
    assert_equal "Title Second", title.join("a")
    assert_nil title.join("z")
  end

  def test_add_appends_a_subfield
    field = title
    result = field.add("n", "Part 1")

    assert_same field, result
    assert_equal Subfield.new("n", "Part 1"), field.subfields.last
  end

  def test_remove_returns_the_removed_subfields
    field = title
    removed = field.remove("a")

    assert_equal ["Title", "Second"], removed.map(&:value)
    assert_equal ["b", "c"], field.subfields.map(&:code)
  end

  def test_remove_needs_codes
    field = title
    error = assert_raises(ArgumentError) { field.remove(*[]) }

    assert_match(/subfields\.clear/, error.message)
    assert_equal 4, field.subfields.size
  end

  def test_codes_in_an_array
    assert_equal ["Title", "Subtitle", "Second"], title.values(["a", "b"])
    assert_equal "Subtitle", title.value(["b"])
    assert_equal ["Title", "Second"], title.remove(["a"]).map(&:value)
  end

  def test_rejects_codes_that_are_not_strings
    assert_raises(ArgumentError) { title.values(/a/) }
    assert_raises(ArgumentError) { title.subfields(:a) }
  end

  def test_equality_compares_tag_indicators_and_subfield_order
    assert_equal title, title
    refute_equal title, DataField.new("245", "1", "0", title.subfields.reverse)
    refute_equal title, DataField.new("245", "0", "0", title.subfields)
  end

  def test_equal_fields_have_the_same_hash
    assert_equal title.hash, title.hash
  end

  def test_to_h_is_marc_in_json
    expected = {"650" => {"ind1" => " ", "ind2" => "7", "subfields" => [{"a" => "Metadata"}, {"2" => "gnd"}]}}

    assert_equal expected, DataField.new("650", " ", "7", [["a", "Metadata"], ["2", "gnd"]]).to_h
  end

  def test_text_form_shows_blank_indicators_as_backslash
    field = DataField.new("650", " ", "7", [["a", "Metadata"], ["2", "gnd"]])

    assert_equal "=650  \\7$aMetadata$2gnd", field.to_s
    assert_equal field.to_s, field.inspect
  end

  def test_dup_copies_subfields_and_strings
    original = title
    copy = original.dup
    copy.subfields.first.value << "!"
    copy.add("x", "new")

    assert_equal "Title", original.value("a")
    assert_equal 4, original.subfields.size
  end

  def test_dup_with_a_nil_tag
    assert_nil DataField.new(nil).dup.tag
  end

  def test_the_tag_is_frozen_and_fixed
    field = DataField.new(+"245")

    assert_predicate field.tag, :frozen?
    refute_respond_to field, :tag=
  end

end
