# frozen_string_literal: true

require "test_helper"

class NumberFormatsTest < Minitest::Test

  NumberFormats = Metacrunch::Xlsx::NumberFormats

  KINDS = {
    "yyyy-mm-dd" => :date, "dd/mm/yyyy" => :date, "dd/mm/yyyy;@" => :date, "[$-F800]dddd, mmmm dd, yyyy" => :date,
    "d-mmm" => :date, "mmm-yy" => :date, "MM/DD/YYYY" => :date,
    "[DBNum1][$-804]yyyy\"年\"m\"月\"d\"日\"" => :date,
    "yyyy-mm-dd hh:mm:ss" => :date_time, "m/d/yy h:mm" => :date_time, "d.m.yyyy h:mm AM/PM" => :date_time,
    "h:mm" => :time, "[$-409]h:mm AM/PM;@" => :time, "mm:ss" => :time, "mm:ss.0" => :time, "h:mm a/p" => :time,
    "[h]:mm:ss" => :duration, "[mm]:ss" => :duration, "[ss]" => :duration, "[H]:MM" => :duration,
    "General" => :number, "0.00" => :number, "@" => :number, "\"Q\"0" => :number, "0.00\" kg\"" => :number,
    "[Red]0.00" => :number, "#,##0.00 \"d\"" => :number, "0;[Red]-0" => :number, "\\d0" => :number,
    "0.00E+00" => :number, "_(* #,##0_);_(* (#,##0);_(* \"-\"_);_(@_)" => :number, "[$€-407] #,##0.00" => :number,
    "# ?/?" => :number, "\"Mon\"" => :number, "\"a;\"yyyy" => :date
  }.freeze

  BUILT_IN = {0 => :number, 1 => :number, 9 => :number, 14 => :date, 17 => :date, 18 => :time, 21 => :time,
              22 => :date_time, 27 => :date, 36 => :date, 45 => :time, 46 => :duration, 47 => :time, 49 => :number,
              50 => :date, 58 => :date, 59 => :number, 164 => :number}.freeze

  def test_custom_codes
    KINDS.each { |code, kind| assert_equal kind, NumberFormats.kind(164, code), code }
  end

  def test_built_in_ids
    BUILT_IN.each { |id, kind| assert_equal kind, NumberFormats.kind(id), id }
  end

  # styles.xml may give a code for a built-in id; the code decides.
  def test_a_code_decides_over_the_id
    assert_equal :number, NumberFormats.kind(14, "0.00")
  end

end
