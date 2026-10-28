# frozen_string_literal: true

require "test_helper"

class KeyTemplateTest < Minitest::Test

  KeyTemplate = Metacrunch::Redis::KeyTemplate

  def test_fills_in_fields_given_as_strings_or_symbols
    template = KeyTemplate.new("book:%{isbn}")

    assert_equal ["book:978", "book:979"], [template.key({"isbn" => "978"}), template.key({isbn: "979"})]
  end

  def test_takes_integers_and_several_placeholders
    assert_equal "title:7:en",
                 KeyTemplate.new("%{type}:%{id}:%{lang}").key({"type" => "title", "id" => 7, "lang" => "en"})
  end

  def test_a_template_without_placeholders_is_one_key_for_any_record
    assert_equal ["latest", "latest"], [KeyTemplate.new("latest").key({"a" => 1}), KeyTemplate.new("latest").key("x")]
  end

  def test_to_s_is_the_template
    assert_equal "book:%{isbn}", KeyTemplate.new("book:%{isbn}").to_s
  end

  def test_refuses_records_that_give_no_key
    template = KeyTemplate.new("book:%{isbn}")
    {
      "978" => "record is a String, not a Hash",
      {} => "no value for isbn in the key book:%{isbn}",
      {"isbn" => nil} => "no value for isbn in the key book:%{isbn}",
      {"isbn" => ""} => "no value for isbn in the key book:%{isbn}",
      {"isbn" => {"a" => 1}} => "isbn is a Hash; a key takes Strings and Integers",
      {"isbn" => 9.5} => "isbn is a Float; a key takes Strings and Integers"
    }.each do |record, message|
      error = assert_raises(Metacrunch::Redis::Error) { template.key(record) }

      assert_equal message, error.message
    end
  end

end
