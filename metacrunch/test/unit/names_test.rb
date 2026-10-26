# frozen_string_literal: true

require "test_helper"

class NamesTest < Minitest::Test

  Names = Metacrunch::Names

  VALID = ["a2c", "catalog:reindex", "es:create-index", "marc_to_json", "2go", "a:b:c"].freeze
  INVALID = ["", "A2c", "-a", "_a", "a:", ":a", "a::b", "a b", "a.b", "a/b", "ä", "a:-b"].freeze

  def test_accepts_valid_names
    assert_equal(VALID, VALID.map { Names.check!(it, "job") })
  end

  def test_rejects_invalid_names
    rejected = INVALID.select do |name|
      Names.check!(name, "job")
      false
    rescue ArgumentError
      true
    end

    assert_equal INVALID, rejected
  end

  def test_symbols_are_names_too
    assert_equal "a2c", Names.check!(:a2c, "job")
  end

  def test_the_message_names_the_kind_and_the_rule
    error = assert_raises(ArgumentError) { Names.check!("Catalog", "command") }

    assert_equal "invalid command name \"Catalog\": use a-z, 0-9, _ and -, in parts separated by :", error.message
  end

  def test_other_objects_are_no_names
    assert_raises(ArgumentError) { Names.check!(42, "job") }
  end

  def test_valid_takes_strings_only
    assert_equal([true, false, false], ["es:create-index", "Es", :a2c].map { Names.valid?(it) })
  end

  def test_reserved_names_are_the_builtin_commands
    assert_equal [*Metacrunch::Cli::COMMANDS.keys, "help"].sort, Names::RESERVED.sort
    assert Names.reserved?("run")
    refute Names.reserved?("catalog")
  end

  def test_paths_contain_a_slash_or_a_dot
    assert_equal([true, true, true, false], ["jobs/a2c", "a2c.rb", "./a2c", "a2c"].map { Names.path?(it) })
  end

  def test_descriptions_are_one_line_or_nil
    assert_equal "Load the catalog", Names.check_desc!("Load the catalog")
    assert_nil Names.check_desc!(nil)
    assert_raises(ArgumentError) { Names.check_desc!("two\nlines") }
  end

  def test_descriptions_are_strings
    error = assert_raises(ArgumentError) { Names.check_desc!(:catalog) }

    assert_equal "desc must be one line of text, got :catalog", error.message
  end

end
