# frozen_string_literal: true

require "test_helper"

class ValuesTest < Minitest::Test

  TABLE = Metacrunch::Db::Table.new("books")
  COLUMNS = Set[:isbn, :title, :year, :doc]

  # An object Sequel writes itself, as the wrappers of its extensions do.
  class Literal

    def sql_literal_append(_dataset, sql)
      sql << "'x'"
    end

  end

  def test_a_hash_with_string_or_symbol_keys_becomes_symbol_columns
    assert_equal({isbn: "1", title: "A"}, row({"isbn" => "1", :title => "A"}))
  end

  def test_not_a_hash_fails
    assert_failure("record is a String, not a Hash") { row("isbn") }
    assert_failure("record is an Array, not a Hash") { row([1]) }
  end

  def test_a_record_without_columns_fails
    assert_failure("record has no columns") { row({}) }
  end

  def test_a_key_that_is_no_string_or_symbol_fails
    assert_failure("record has the key 1 (an Integer); keys are column names") { row({1 => "x"}) }
  end

  def test_unknown_columns_fail_with_their_names
    assert_failure("books has no column Title") { row({"isbn" => "1", "Title" => "A"}) }
    assert_failure("books has no columns a, b") { row({"a" => 1, "isbn" => "1", "b" => 2}) }
  end

  def test_no_schema_skips_the_column_check
    assert_equal({anything: 1}, row({"anything" => 1}, columns: nil))
  end

  def test_a_column_given_as_string_and_symbol_fails
    assert_failure("title is given twice") { row({"title" => "a", :title => "b"}) }
  end

  def test_a_key_without_value_fails
    assert_failure("no value for key isbn") { row({"title" => "A"}, action: :upsert) }
    assert_failure("no value for key isbn") { row({"isbn" => nil, "title" => "A"}, action: :update) }
    assert_failure("no value for key year") { row({"isbn" => "1"}, action: :delete, key: [:isbn, :year]) }
  end

  def test_insert_needs_no_key_value
    assert_equal({title: "A"}, row({"title" => "A"}))
  end

  def test_delete_keeps_only_the_key_columns
    assert_equal({isbn: "1"}, row({"isbn" => "1", "title" => {"no" => "check"}}, action: :delete))
  end

  def test_allowed_values_pass
    values = ["text", Sequel.blob("\xFF".b), 1, 1.5, BigDecimal("1.25"), true, false, Date.new(2026, 1, 2),
              DateTime.new(2026, 1, 2, 3, 4, 5), Time.now, Sequel.lit("now()"), Literal.new]

    values.each { |value| assert_same value, row({"title" => value})[:title] }
    assert_nil row({"title" => nil})[:title]
  end

  def test_a_hash_or_array_value_fails_with_a_json_hint
    assert_failure("doc is a Hash; write JSON.generate(value) for a JSON column") { row({"doc" => {"a" => 1}}) }
    assert_failure("doc is an Array; write JSON.generate(value) for a JSON column") { row({"doc" => [1]}) }
  end

  def test_a_symbol_value_fails
    assert_failure("title is a Symbol; write a String") { row({"title" => :title}) }
  end

  def test_other_objects_fail
    assert_failure("title is a Set; turn it into a String or a number in a step") { row({"title" => Set[1]}) }
    assert_failure("title is an Object; turn it into a String or a number in a step") { row({"title" => Object.new}) }
  end

  def test_invalid_strings_fail
    assert_failure("title is not valid UTF-8") { row({"title" => "\xFF"}) }
    assert_failure("title is not valid Shift_JIS") { row({"title" => "\x81".dup.force_encoding("Shift_JIS")}) }
  end

  def test_binary_strings_pass
    assert_equal "\xFF".b, row({"title" => "\xFF".b})[:title]
  end

  private

  def row(record, columns: COLUMNS, key: [:isbn], action: :insert)
    Metacrunch::Db::Values.row(record, table: TABLE, columns:, key:, action:)
  end

  def assert_failure(message, &)
    error = assert_raises(Metacrunch::Db::Error, &)

    assert_equal message, error.message
  end

end
