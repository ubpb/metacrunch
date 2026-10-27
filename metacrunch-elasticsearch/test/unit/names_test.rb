# frozen_string_literal: true

require "test_helper"

class NamesTest < Minitest::Test

  Names = Metacrunch::Elasticsearch::Names

  def test_valid_names_pass
    ["books", "books-20261026-153000", ".hidden", "a_b+c", "x" * 255].each do |name|
      assert_equal name, Names.check(name, "index")
    end
  end

  def test_targets_of_a_reader_are_names_aliases_or_patterns
    assert_equal ["books"], Names.targets("books")
    assert_equal ["books-*", "papers"], Names.targets(["books-*", "papers"])
    assert_raises(ArgumentError) { Names.targets([]) }
  end

  def test_names_against_elasticsearch_s_rules
    {
      :books => "it must be a String",
      "" => "it is empty",
      "Books" => "it has uppercase letters",
      "books*" => 'it contains "*"',
      "a b" => 'it contains " "',
      "a:b" => 'it contains ":"',
      "_books" => "it starts with _",
      ".." => "it is ..",
      "x" * 256 => "it is longer than 255 bytes"
    }.each do |name, problem|
      assert_equal "alias #{name.inspect} is not a valid name: #{problem}",
                   assert_raises(ArgumentError) { Names.check(name, "alias") }.message
    end
  end

end
