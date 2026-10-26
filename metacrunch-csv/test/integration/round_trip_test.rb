# frozen_string_literal: true

require "test_helper"

# What the writer writes, the reader reads back.
class RoundTripTest < Minitest::Test

  include Helpers

  RECORDS = [
    {"id" => "00123", "title" => %(The "quoted", title), "note" => ""},
    {"id" => "0306406152", "title" => "two\nlines", "note" => " spaces "},
    {"id" => "3", "title" => "Müller; Ærø", "note" => "€"}
  ].freeze

  def test_strings_and_empty_strings_come_back
    assert_equal RECORDS, read(written(RECORDS))
  end

  def test_with_options_for_excel
    options = {col_sep: ";", encoding: "Windows-1252"}

    assert_equal RECORDS, read(written(RECORDS, **options), **options)
  end

  def test_utf16le_with_bom_and_tabs
    bytes = written(RECORDS, col_sep: "\t", encoding: "UTF-16LE", bom: true)

    assert_equal RECORDS, read(bytes, col_sep: "\t", encoding: "UTF-16LE")
  end

  def test_nil_comes_back_as_an_empty_string
    assert_equal [{"id" => "1", "note" => ""}], read(written([{"id" => "1", "note" => nil}]))
  end

  def test_one_column_keeps_every_record
    records = [{"note" => "a"}, {"note" => nil}, {"note" => ""}, {"note" => "b"}]

    assert_equal(["a", "", "", "b"], read(written(records)).map { it["note"] })
  end

end
