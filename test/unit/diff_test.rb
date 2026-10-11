# frozen_string_literal: true

require "test_helper"
require "metacrunch/diff"

class DiffTest < Minitest::Test

  def test_removed_added_and_changed_keys_in_that_order
    changes = diff({"_id" => 1, "title" => "a", "x" => 1}, {"title" => "b", "x" => 1, "id" => 1})

    assert_equal [[:removed, "_id", 1, nil], [:added, "id", nil, 1], [:changed, "title", "a", "b"]], changes
  end

  def test_nested_hashes_are_compared_by_path
    changes = diff({"meta" => {"source" => "ris", "v" => 1}}, {"meta" => {"source" => "fis", "v" => 1}})

    assert_equal [[:changed, "meta.source", "ris", "fis"]], changes
  end

  def test_arrays_and_replaced_hashes_are_compared_as_a_whole
    assert_equal [[:changed, "isbns", [1], [1, 2]]], diff({"isbns" => [1]}, {"isbns" => [1, 2]})
    assert_equal [[:changed, "meta", {"a" => 1}, "x"]], diff({"meta" => {"a" => 1}}, {"meta" => "x"})
  end

  def test_equal_records_have_no_changes_and_symbol_keys_become_paths
    assert_empty diff({"a" => [1]}, {"a" => [1]})
    assert_equal [[:added, "b", nil, 2]], diff({a: 1}, {a: 1, b: 2})
  end

  private

  def diff(before, after)
    Metacrunch::Diff.changes(before, after).map { it.to_h.values }
  end

end
