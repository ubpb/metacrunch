# frozen_string_literal: true

require "test_helper"

class TextTest < Minitest::Test

  RULES = <<~MARKDOWN
    ---
    title: Library rules
    source: https://www.example.org/rules.pdf
    lang: en
    author: Library board
    ---
    # Using the library
  MARKDOWN

  def test_crlf_and_invalid_bytes
    assert_equal({text: "a\nb�", title: nil, lang: nil, fields: {}, mark: nil}, extract("a\r\nb\xFF".b))
  end

  def test_a_bom_is_dropped
    assert_equal "# Rules", extract("\xEF\xBB\xBF# Rules".b)[:text]
  end

  def test_utf16_with_a_bom
    ["UTF-16LE", "UTF-16BE"].each do |encoding|
      bytes = "﻿Öffnungszeiten\r\n".encode(encoding).b

      assert_equal "Öffnungszeiten\n", extract(bytes)[:text], encoding
    end
  end

  def test_a_string_in_another_encoding
    assert_equal "Öffnungszeiten", extract("Öffnungszeiten".encode(Encoding::ISO_8859_1))[:text]
  end

  def test_nil_is_empty
    assert_equal "", extract(nil)[:text]
  end

  def test_front_matter_gives_title_lang_and_fields
    assert_equal({text: "# Using the library\n", title: "Library rules", lang: "en",
                  fields: {"source" => "https://www.example.org/rules.pdf", "author" => "Library board"}, mark: nil},
                 extract(RULES))
  end

  def test_front_matter_values_become_json_values
    markdown = "---\ndate: 2026-11-03\nupdated: 2026-11-03 10:00:00 +01:00\ntags: [loans, fees]\n" \
               "meta: {level: 1}\n1: one\n---\nx"

    assert_equal({"date" => "2026-11-03", "updated" => "2026-11-03T10:00:00+01:00", "tags" => ["loans", "fees"],
                  "meta" => {"level" => 1}, "1" => "one"}, extract(markdown)[:fields])
  end

  def test_front_matter_closed_by_dots_and_empty_front_matter
    assert_equal ["x", {"title" => "Rules"}], [extract("---\n---\nx")[:text], extract("---\ntitle: Rules\n...\nx")
      .then { {"title" => it[:title]} }]
  end

  def test_a_rule_at_the_start_is_no_front_matter
    text = "---\nJust a line between rules\n---\nx"

    assert_equal [text, {}, nil], extract(text).values_at(:text, :fields, :mark)
  end

  def test_unreadable_front_matter_stays_text_with_a_mark
    ["---\ntitle: [unclosed\n---\nx", "---\nobject: !ruby/object:Object {}\n---\nx"].each do |text|
      assert_equal [text, {}, "Front matter not read"], extract(text).values_at(:text, :fields, :mark), text
    end
  end

  def test_types
    assert_equal ["text/plain", "text/markdown"], Metacrunch::Ai::Text.new.types
  end

  private

  def extract(content) = Metacrunch::Ai::Text.new.extract(content, type: "text/markdown")

end
