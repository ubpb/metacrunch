# frozen_string_literal: true

require "test_helper"

# The writer against each database (see test/support/integration.rb).
module WritingTests

  def test_inserts_upserts_updates_and_deletes
    name = create_books([{isbn: "1", title: "Old", year: 1999}])
    write([{"isbn" => "2", "title" => "B", "year" => 2002}, {"isbn" => "3", "title" => "C"}], table: name)
    write([{"isbn" => "1", "title" => "New"}, {"isbn" => "4", "title" => "D"}],
          table: name, action: :upsert, key: "isbn")
    write([{"isbn" => "3", "year" => 2003}], table: name, action: :update, key: "isbn")
    write([{"isbn" => "2"}, {"isbn" => "9"}], table: name, action: :delete, key: "isbn")

    assert_equal [["1", "New", 1999], ["3", "C", 2003], ["4", "D", nil]], stored(name)
  end

  def test_upsert_keeps_the_last_record_of_a_key
    name = create_books
    write([{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "B"}, {"isbn" => "1", "title" => "C"}],
          table: name, action: :upsert, key: "isbn")

    assert_equal [["1", "C", nil], ["2", "B", nil]], stored(name)
  end

  def test_an_update_to_the_same_values_counts_as_written
    name = create_books([{isbn: "1", title: "A", year: 1}])

    assert_nil write([{"isbn" => "1", "title" => "A"}], table: name, action: :update, key: "isbn")
  end

  def test_refused_rows_are_failures
    name = create_books([{isbn: "1", title: "Taken", year: 1}])
    database.alter_table(name.to_sym) { set_column_not_null :title }
    records = [{"isbn" => "1", "title" => "Again"}, {"isbn" => "2", "title" => nil}, {"isbn" => "3", "title" => "C"},
               {"isbn" => "4", "title" => "x" * 101}]
    error = assert_raises(Metacrunch::SinkFailures) { write(records, table: name) }
    refused = {0 => Sequel::UniqueConstraintViolation, 1 => Sequel::NotNullConstraintViolation}
    refused[3] = Sequel::DatabaseError unless type == :sqlite # SQLite stores longer text

    assert_equal refused, error.failed.transform_values(&:class)
    assert_includes stored(name).map(&:first), "3"
  end

  # MariaDB takes statements of up to 16 MB (max_allowed_packet): a batch of 20 MB goes in pieces of max_bytes.
  def test_a_batch_larger_than_a_packet_goes_in_pieces
    name = table("texts")
    text_type = type == :mysql ? "longtext" : "text"
    database.create_table(name.to_sym) do
      Integer :id, primary_key: true
      column :body, text_type
    end
    body = "x" * 1_000_000
    write((1..20).map { {"id" => it, "body" => body} }, table: name)

    assert_equal 20, database[name.to_sym].count
  end

  def test_max_bytes_splits_a_batch
    name = create_books
    write((1..30).map { {"isbn" => it.to_s, "title" => "t" * 90} }, table: name, max_bytes: 1000)

    assert_equal 30, database[name.to_sym].count
  end

  def test_open_checks_the_table
    name = create_books
    error = assert_raises(Metacrunch::OutputError) { write([], table: table("nope")) }

    assert_equal "db #{table("nope")}: no such table", error.message
    error = assert_raises(Metacrunch::OutputError) { write([], table: name, action: :upsert, key: "year") }

    assert_equal "db #{name}: key year is neither the primary key nor a unique index of #{name}", error.message
  end

  def test_upserts_by_a_unique_index
    name = create_books([{isbn: "1", title: "A", year: 1}])
    database.add_index(name.to_sym, :title, unique: true)
    write([{"isbn" => "1", "title" => "A", "year" => 2}], table: name, action: :upsert, key: "title")

    assert_equal [["1", "A", 2]], stored(name)
  end

  def test_writes_to_a_qualified_table
    name = create_books
    write([{"isbn" => "1", "title" => "A"}], table: "#{schema}.#{name}", action: :upsert, key: "isbn")

    assert_equal [["1", "A", nil]], stored(name)
  end

end

Integration.define("Writing", WritingTests)
