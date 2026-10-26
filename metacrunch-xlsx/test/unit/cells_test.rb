# frozen_string_literal: true

require "test_helper"

class CellsTest < Minitest::Test

  Cells = Metacrunch::Xlsx::Cells

  def test_column_letters
    assert_equal(["A", "Z", "AA", "AZ", "ZZ", "AAA", "XFD"], [0, 25, 26, 51, 701, 702, 16_383].map { Cells.column(it) })
  end

  def test_nil_is_no_cell
    assert_nil Cells.cell(nil, "A1")
  end

  def test_strings_are_inline_text
    assert_equal '<c r="A1" t="inlineStr"><is><t>00123</t></is></c>', Cells.cell("00123", "A1")
  end

  def test_text_is_escaped
    assert_equal "<t>a &lt;b&gt; &amp; &quot;c&quot;</t>", Cells.text_element(%(a <b> & "c"))
  end

  def test_spaces_at_the_ends_are_preserved
    assert_equal '<t xml:space="preserve"> a </t>', Cells.text_element(" a ")
  end

  def test_character_codes_are_escaped
    assert_equal "<t>_x005F_x0041_ and _x005F_x00e9_</t>", Cells.text_element("_x0041_ and _x00e9_")
  end

  def test_chained_character_codes_are_escaped
    assert_equal "<t>_x005F_x0041_x005F_x0042_</t>", Cells.text_element("_x0041_x0042_")
  end

  # XML turns "\r\n" and "\r" into "\n"; Excel writes a carriage return so.
  def test_carriage_returns_are_character_codes
    assert_equal "<t>a_x000D_\nb_x000D_c</t>", Cells.text_element("a\r\nb\rc")
  end

  def test_text_in_another_encoding_is_written_as_utf8
    assert_equal "<t>Müller</t>", Cells.text_element("Müller".encode(Encoding::ISO_8859_1))
  end

  def test_integers_and_floats_are_numbers
    assert_equal '<c r="B2"><v>-42</v></c>', Cells.cell(-42, "B2")
    assert_equal '<c r="B2"><v>1.5</v></c>', Cells.cell(1.5, "B2")
  end

  def test_fifteen_digits_are_a_number
    assert_equal '<c r="A1"><v>999999999999999</v></c>', Cells.cell(999_999_999_999_999, "A1")
  end

  # As from a database's NUMERIC column.
  def test_big_decimals_are_numbers
    assert_equal '<c r="A1"><v>123.45</v></c>', Cells.cell(BigDecimal("123.45"), "A1")
    assert_equal '<c r="A1"><v>100000000000000000000.0</v></c>', Cells.cell(BigDecimal("1e20"), "A1")
  end

  def test_unwritable_big_decimals
    {
      BigDecimal("1234567890.123456") => "has more than 15 significant digits, which Excel cannot keep; turn it into " \
                                         "a String in a step",
      BigDecimal("NaN") => "is NaN, which Excel cannot store",
      BigDecimal("-Infinity") => "is -Infinity, which Excel cannot store"
    }.each do |value, message|
      assert_equal message, assert_raises(Cells::Unwritable) { Cells.cell(value, "A1") }.message
    end
  end

  def test_booleans
    assert_equal '<c r="A1" t="b"><v>1</v></c>', Cells.cell(true, "A1")
    assert_equal '<c r="A1" t="b"><v>0</v></c>', Cells.cell(false, "A1")
  end

  def test_a_style_is_an_attribute
    assert_equal '<c r="A1" s="1" t="inlineStr"><is><t>id</t></is></c>', Cells.cell("id", "A1", 1)
  end

  def test_unwritable_values
    {
      10**15 => "has more than 15 digits, which Excel cannot keep; turn it into a String in a step",
      Float::NAN => "is NaN, which Excel cannot store",
      -Float::INFINITY => "is -Infinity, which Excel cannot store",
      Time.at(0) => "is a Time; turn it into a String or a number in a step",
      ["a"] => "is an Array; turn it into a String or a number in a step"
    }.each do |value, message|
      assert_equal message, assert_raises(Cells::Unwritable) { Cells.cell(value, "A1") }.message
    end
  end

  def test_unwritable_text
    {
      "a\u0001" => "has a character that XML does not allow",
      "a" * 32_768 => "has more than 32767 characters",
      "a\xFF".dup.force_encoding(Encoding::UTF_8) => "is not valid UTF-8",
      "a\xFF".b => "has no UTF-8 form (it is ASCII-8BIT)"
    }.each do |value, message|
      assert_equal message, assert_raises(Cells::Unwritable) { Cells.cell(value, "A1") }.message
    end
  end

  def test_the_longest_text_and_tabs_and_line_breaks_are_written
    assert_equal 32_767, Cells.text_element("a" * 32_767).count("a")
    assert_equal "<t>a\tb\nc</t>", Cells.text_element("a\tb\nc")
  end

end
