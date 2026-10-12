# frozen_string_literal: true

require "test_helper"

class SubfieldTest < Minitest::Test

  Subfield = Metacrunch::Marcxml::Subfield

  def test_has_a_code_and_a_value
    subfield = Subfield.new("a", "Title")

    assert_equal "a", subfield.code
    assert_equal "Title", subfield.value
  end

  def test_equal_with_the_same_code_and_value
    assert_equal Subfield.new("a", "x"), Subfield.new("a", "x")
    assert_operator Subfield.new("a", "x"), :eql?, Subfield.new("a", "x")
    assert_equal Subfield.new("a", "x").hash, Subfield.new("a", "x").hash
  end

  def test_not_equal_with_another_code_or_value
    refute_equal Subfield.new("a", "x"), Subfield.new("b", "x")
    refute_equal Subfield.new("a", "x"), Subfield.new("a", "y")
  end

  def test_to_h_is_marc_in_json
    assert_equal({"a" => "Title"}, Subfield.new("a", "Title").to_h)
  end

  def test_text_form
    assert_equal "$aTitle", Subfield.new("a", "Title").to_s
    assert_equal "$aTitle", Subfield.new("a", "Title").inspect
  end

  def test_dup_copies_the_strings
    original = Subfield.new("a", +"Title")
    copy = original.dup
    copy.value << "!"

    assert_equal "Title", original.value
  end

  def test_dup_with_nil_code_and_value
    assert_equal Subfield.new(nil, nil), Subfield.new(nil, nil).dup
  end

end
