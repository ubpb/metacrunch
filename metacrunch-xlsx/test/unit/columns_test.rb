# frozen_string_literal: true

require "test_helper"

# The same tests as in metacrunch-csv; only this constant differs.
class ColumnsTest < Minitest::Test

  Columns = Metacrunch::Xlsx::Columns

  include Helpers

  def test_described_names_the_class_with_its_article
    assert_equal(["an Array", "a Time"], [[], Time.at(0)].map { Columns.described(it) })
  end

  def test_described_names_the_nearest_named_class_of_an_anonymous_one
    assert_equal "a Data", Columns.described(Data.define(:x).new(x: 1))
  end

  def test_without_columns_nothing_is_known
    columns = Columns.new(nil)

    refute_predicate columns, :known?
    assert_nil columns.names
  end

  def test_an_array_names_the_keys_and_the_header
    columns = Columns.new(["id", "title"])

    assert_equal ["id", "title"], columns.names
    assert_equal ["2", "Moby"], columns.row({"title" => "Moby", "id" => "2", "year" => "1851"}, ctx)
  end

  def test_a_hash_maps_header_names_to_keys
    columns = Columns.new({"ID" => "id", "Titel" => "title"})

    assert_equal ["ID", "Titel"], columns.names
    assert_equal ["2", "Moby"], columns.row({"title" => "Moby", "id" => "2"}, ctx)
  end

  def test_missing_keys_are_nil
    assert_equal ["2", nil], Columns.new(["id", "title"]).row({"id" => "2"}, ctx)
  end

  def test_invalid_columns_are_argument_errors
    [:id, "id", [], ["a", "a"], ["", "b"], [1], {"A" => 1}, {"A" => ""}, {a: "a"}].each do |columns|
      assert_raises(ArgumentError) { Columns.new(columns) }
    end
  end

  def test_a_named_column_twice_names_it
    error = assert_raises(ArgumentError) { Columns.new(["a", "b", "a"]) }

    assert_equal 'the column "a" is named twice', error.message
  end

  def test_the_first_record_defines_the_columns
    columns = Columns.new(nil)
    columns.row({"id" => "1", "title" => "Moby"}, ctx)

    assert_equal ["id", "title"], columns.names
    assert_equal ["2", nil], columns.row({"id" => "2"}, ctx(2))
  end

  def test_symbol_keys_give_string_names
    columns = Columns.new(nil)

    assert_equal ["1"], columns.row({id: "1"}, ctx)
    assert_equal ["id"], columns.names
  end

  def test_a_new_key_without_columns_stops_the_run
    columns = Columns.new(nil)
    columns.row({"id" => "1"}, ctx)
    error = assert_raises(Metacrunch::Error) { columns.row({"id" => "7", "isbn" => "x"}, ctx(7)) }

    assert_equal 'record at position 7 has the key "isbn", which the first record does not have; ' \
                 "name the columns with columns:", error.message
  end

  def test_with_columns_symbol_keys_are_found_by_name
    assert_equal ["1", "Moby"], Columns.new({"ID" => "id", "Titel" => "title"}).row({id: "1", title: "Moby"}, ctx)
  end

  def test_a_string_key_comes_before_its_symbol
    assert_equal ["1"], Columns.new(["id"]).row({id: "2"}.merge("id" => "1"), ctx)
  end

  def test_with_columns_other_keys_are_ignored
    assert_equal ["1"], Columns.new(["id"]).row({"id" => "1", "isbn" => "x"}, ctx)
  end

  def test_arrays_are_rows_as_they_are
    columns = Columns.new(nil)

    assert_equal ["1", 2], columns.row(["1", 2], ctx)
    refute_predicate columns, :known?
  end

  def test_an_array_longer_than_the_columns_is_an_error
    error = assert_raises(Metacrunch::Error) { Columns.new(["a", "b"]).row([1, 2, 3], ctx(4)) }

    assert_equal "record at position 4 has 3 values for 2 columns", error.message
  end

  def test_hashes_and_arrays_do_not_mix
    columns = Columns.new(nil)
    columns.row({"a" => 1}, ctx)
    error = assert_raises(Metacrunch::Error) { columns.row([1], ctx(2)) }

    assert_equal "record at position 2 is an Array, the records before it are Hashes; write either Hashes or Arrays",
                 error.message
  end

  def test_arrays_and_hashes_do_not_mix
    columns = Columns.new(nil)
    columns.row([1], ctx)
    error = assert_raises(Metacrunch::Error) { columns.row({"a" => 1}, ctx(2)) }

    assert_match(/is a Hash, the records before it are Arrays/, error.message)
  end

  def test_other_records_are_errors
    error = assert_raises(Metacrunch::Error) { Columns.new(nil).row("1,2", ctx(3)) }

    assert_equal "record at position 3 is a String, not a Hash or an Array", error.message
  end

end
