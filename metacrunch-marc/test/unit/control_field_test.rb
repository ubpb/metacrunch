# frozen_string_literal: true

require "test_helper"

class ControlFieldTest < Minitest::Test

  ControlField = Metacrunch::Marc::ControlField

  def test_has_a_tag_and_a_value
    field = ControlField.new("001", "123")

    assert_equal "001", field.tag
    assert_equal "123", field.value
  end

  def test_brackets_read_positions_of_the_value
    field = ControlField.new("008", "#{"x" * 35}ger d")

    assert_equal "ger", field[35..37]
    assert_equal "g", field[35]
  end

  def test_brackets_on_a_nil_value
    assert_nil ControlField.new("008", nil)[35..37]
  end

  def test_equality
    assert_equal ControlField.new("001", "1"), ControlField.new("001", "1")
    refute_equal ControlField.new("001", "1"), ControlField.new("003", "1")
    assert_equal ControlField.new("001", "1").hash, ControlField.new("001", "1").hash
  end

  def test_to_h_is_marc_in_json
    assert_equal({"001" => "123"}, ControlField.new("001", "123").to_h)
  end

  def test_text_form
    assert_equal "=001  123", ControlField.new("001", "123").to_s
    assert_equal "=001  123", ControlField.new("001", "123").inspect
  end

  def test_dup_copies_the_strings
    original = ControlField.new("001", +"123")
    copy = original.dup
    copy.value << "4"

    assert_equal "123", original.value
  end

  def test_dup_with_nil_tag_and_value
    assert_equal ControlField.new(nil, nil), ControlField.new(nil, nil).dup
  end

  def test_the_tag_is_frozen_and_fixed
    field = ControlField.new(+"001", "1")

    assert_predicate field.tag, :frozen?
    refute_respond_to field, :tag=
  end

end
