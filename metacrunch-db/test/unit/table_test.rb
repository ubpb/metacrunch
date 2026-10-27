# frozen_string_literal: true

require "test_helper"

class TableTest < Minitest::Test

  def test_a_plain_name_is_a_symbol
    table = Metacrunch::Db::Table.new("books")

    assert_equal :books, table.identifier
    assert_equal "books", table.to_s
  end

  def test_a_dotted_name_is_qualified
    table = Metacrunch::Db::Table.new("library.books")

    assert_equal Sequel[:library][:books], table.identifier
    assert_equal "library.books", table.to_s
  end

  def test_a_symbol_is_taken
    assert_equal :Books, Metacrunch::Db::Table.new(:Books).identifier
    assert_equal "x$y", Metacrunch::Db::Table.new("x$y").to_s
  end

  def test_other_names_are_refused
    ["a b", "a.b.c", "", "1a", "a;drop", ".a", "a."].each do |name|
      error = assert_raises(ArgumentError) { Metacrunch::Db::Table.new(name) }

      assert_equal "table must be a name such as books or library.books, got #{name.inspect}", error.message
    end
    assert_raises(ArgumentError) { Metacrunch::Db::Table.new(nil) }
  end

end
