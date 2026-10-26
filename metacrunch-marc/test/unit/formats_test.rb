# frozen_string_literal: true

require "test_helper"

class FormatsTest < Minitest::Test

  Marc = Metacrunch::Marc
  Formats = Metacrunch::Marc::Formats

  def test_markup_is_marcxml
    assert_equal :xml, detect(%(<?xml version="1.0"?>))
    assert_equal :xml, detect("\xEF\xBB\xBF\n  <collection>".b)
  end

  def test_an_object_is_marc_in_json
    assert_equal :json, detect(%({"fields": []}\n))
  end

  def test_a_record_length_and_a_base_address_are_iso2709
    assert_equal :iso2709, detect("00067nam a2200049 c 4500001")
    assert_equal :iso2709, detect("\r\n\0 00067nam a2200049 c 4500")
  end

  def test_digits_without_a_base_address_are_not_marc
    assert_equal :unknown, detect("2024;title;author;year\n")
    assert_equal :unknown, detect("12345")
  end

  def test_an_array
    assert_equal :array, detect(%([{"fields": []}]))
  end

  def test_nothing_but_skipped_bytes
    assert_equal :none, detect("")
    assert_equal :none, detect(" \n\t\r\0")
    assert_equal :none, detect(" " * 1_000)
  end

  def test_anything_else_is_not_marc
    assert_equal :unknown, detect("id;title\n1;x\n")
    assert_equal :unknown, detect("\xFF\xFE<\x00".b)
  end

  def test_the_window_grows_past_skipped_bytes
    assert_equal :iso2709, detect("#{" " * 100}00067nam a2200049 c 4500")
    assert_equal :xml, detect("#{"\n" * 70}<record/>")
  end

  def test_an_incomplete_head_asks_for_more
    assert_nil Formats.format(" " * 64, complete: false)
    assert_nil Formats.format("#{" " * 60}0006", complete: false)
    assert_nil Formats.format("\xEF".b, complete: false)
  end

  def test_unknown_names_the_start
    format, head = Formats.detect { "\n\nid;title;author;year\n".b.byteslice(0, it) }

    assert_equal :unknown, format
    assert_equal %(neither MARCXML, ISO 2709 nor MARC-in-JSON: it starts with "id;title;author;"),
                 Formats.unknown(head)
  end

  def test_the_libraries
    assert_equal([Marc::Xml, Marc::Iso2709, Marc::Json], [:xml, :iso2709, :json].map { Formats.library(it) })
  end

  private

  def detect(string) = Formats.detect { string.byteslice(0, it) }.first

end
