# frozen_string_literal: true

require "test_helper"

class ReaderTest < Minitest::Test

  include Databases

  BOOK = {isbn: "9780140449136", title: "Crime and Punishment", year: 1866, price: BigDecimal("12.50"),
          published: Date.new(2003, 1, 30), updated_at: Time.new(2026, 10, 27, 12, 30, 15), available: true}.freeze

  def setup
    super
    create_books(sqlite, [BOOK, {isbn: "9780141439518", title: "Pride and Prejudice", year: 1813}])
  end

  def test_reads_a_table_as_hashes_with_string_keys
    records = reader(table: "books").each.to_a

    assert_equal(["9780140449136", "9780141439518"], records.map { it["isbn"] })
    assert_equal ["isbn", "title", "year", "price", "published", "updated_at", "available"], records.first.keys
  end

  def test_values_keep_sequel_types
    record = reader(table: "books").each.first

    assert_equal BOOK.transform_keys(&:to_s), record
    assert_equal [String, Integer, BigDecimal, Date, Time, TrueClass],
                 record.values_at("title", "year", "price", "published", "updated_at", "available").map(&:class)
  end

  def test_reads_a_qualified_table
    assert_equal 2, reader(table: "main.books").each.count
  end

  def test_reads_sql_with_named_values
    records = reader(query: "SELECT isbn FROM books WHERE year < :year", values: {year: 1850}).each.to_a

    assert_equal [{"isbn" => "9780141439518"}], records
  end

  def test_reads_sql_with_positional_values
    records = reader(query: "SELECT isbn FROM books WHERE year > ? AND title LIKE ?",
                     values: [1850, "Crime%"]).each.to_a

    assert_equal [{"isbn" => "9780140449136"}], records
  end

  def test_reads_sql_without_values
    assert_equal 2, reader(query: "SELECT * FROM books").each.count
  end

  def test_reads_the_dataset_of_a_callable
    given = nil
    query = lambda do |database|
      given = database
      database[:books].where(year: 1813).select(:title)
    end

    assert_equal [{"title" => "Pride and Prejudice"}], reader(query:).each.to_a
    assert_kind_of Sequel::Database, given
  end

  def test_a_callable_must_return_a_dataset
    error = assert_raises(Metacrunch::InputError) { reader(query: ->(_) { [] }).each.to_a }

    assert_equal "db query: the query must return a Sequel::Dataset, got Array", error.message
  end

  def test_needs_table_or_query
    error = assert_raises(ArgumentError) { reader }

    assert_equal "give table: or query:", error.message
  end

  def test_takes_not_both_table_and_query
    error = assert_raises(ArgumentError) { reader(table: "books", query: "SELECT 1") }

    assert_equal "give table: or query:, not both", error.message
  end

  def test_values_need_a_sql_query
    error = assert_raises(ArgumentError) { reader(table: "books", values: [1]) }

    assert_equal "values: needs a SQL query", error.message
    assert_raises(ArgumentError) { reader(query: ->(db) { db[:books] }, values: [1]) }
  end

  def test_values_must_be_a_hash_or_an_array
    error = assert_raises(ArgumentError) { reader(query: "SELECT ?", values: 1) }

    assert_equal "values must be a Hash (for :name placeholders) or an Array (for ?), got 1", error.message
  end

  def test_query_must_be_sql_or_a_callable
    [42, ""].each do |query|
      error = assert_raises(ArgumentError) { reader(query:) }

      assert_equal "query must be SQL (a String) or a callable that returns a Sequel::Dataset, got #{query.inspect}",
                   error.message
    end
  end

  def test_idle_timeout_must_be_a_positive_integer
    [0, -1, 1.5, "60", 2_147_484].each do |idle_timeout|
      error = assert_raises(ArgumentError) { reader(table: "books", idle_timeout:) }

      assert_equal "idle_timeout must be an Integer of seconds from 1 to 2147483, got #{idle_timeout.inspect}",
                   error.message
    end
  end

  def test_count_must_be_true_or_false
    error = assert_raises(ArgumentError) { reader(table: "books", count: "yes") }

    assert_equal "count must be true or false, got \"yes\"", error.message
  end

  def test_open_connects_and_each_uses_that_database
    connection = Databases::FakeConnection.new(sqlite)
    source = Metacrunch::Db::Reader.new(connection, table: "books")
    source.open(context)

    assert_equal 2, source.each.count
    assert_equal 1, connection.connects
  end

  def test_each_without_open_connects
    assert_equal 2, reader(table: "books").each.count
  end

  def test_each_reads_anew_each_time
    source = reader(table: "books")

    assert_equal 2, source.each.count
    sqlite[:books].insert(isbn: "1", title: "New")

    assert_equal 3, source.each.count
  end

  def test_each_returns_the_reader
    source = reader(table: "books")

    assert_same(source, source.each { nil })
    assert_kind_of Enumerator, source.each
  end

  def test_close_disconnects
    connection = Databases::FakeConnection.new(sqlite_connection.connect)
    source = Metacrunch::Db::Reader.new(connection, table: "books")
    source.open(context)
    database = connection.connect
    source.each.first
    source.close

    assert_equal 0, database.pool.size
  end

  def test_close_without_open_does_nothing
    assert_nil reader(table: "books").close
  end

  def test_a_column_twice_stops_before_the_first_record
    query = "SELECT a.isbn, b.isbn FROM books a JOIN books b ON a.isbn = b.isbn"
    records = []
    error = assert_raises(Metacrunch::InputError) { reader(query:).each { records << it } }

    assert_equal "db query: the result has the column isbn twice; name the columns apart (AS)", error.message
    assert_empty records
  end

  def test_progress_is_nil_without_count
    source = reader(table: "books")
    source.each { nil }

    assert_nil source.progress
  end

  def test_count_gives_progress
    sqlite[:books].multi_insert([{isbn: "1", title: "A"}, {isbn: "2", title: "B"}])
    source = reader(table: "books", count: true)

    assert_nil source.progress
    assert_equal([0.25, 0.5, 0.75, 1.0], source.each.map { source.progress })
  end

  def test_progress_of_an_empty_result_is_one
    source = reader(query: "SELECT * FROM books WHERE 0", count: true)
    source.each { nil }

    assert_in_delta 1.0, source.progress
  end

  # A count lower than the rows read: rows were added between the count and the read.
  def test_progress_stays_at_one_when_rows_were_added
    query = ->(database) { database[:books].with_extend(Module.new { def count = 1 }) }
    source = reader(query:, count: true)

    assert_equal([1.0, 1.0], source.each.map { source.progress })
  end

  def test_a_missing_table_is_an_input_error
    error = assert_raises(Metacrunch::InputError) { reader(table: "nope").each.to_a }

    assert_match(/\Adb nope: .*no such table/, error.message)
    assert_kind_of Sequel::DatabaseError, error.cause
  end

  def test_a_failed_connect_is_an_input_error
    connection = Metacrunch::Db::Connection.new(url: "sqlite://#{@dir}/missing/x.db")
    error = assert_raises(Metacrunch::InputError) { Metacrunch::Db::Reader.new(connection, table: "books").each.to_a }

    assert_match(%r{\Adb books: sqlite://#{Regexp.escape(@dir)}/missing/x.db: }, error.message)
  end

  def test_sequel_errors_of_later_steps_pass_unchanged
    error = assert_raises(Sequel::DatabaseError) do
      reader(table: "books").each { raise Sequel::DatabaseError, "from a step" }
    end

    assert_equal "from a step", error.message
  end

  def test_postgres_reads_through_a_cursor
    database, streaming = mock("postgres", :use_cursor)
    records = Metacrunch::Db::Reader.new(Databases::FakeConnection.new(database), table: "books").each.to_a

    assert_equal [[:use_cursor, {rows_per_fetch: 1000}]], streaming.calls
    assert_equal [{"isbn" => "1"}], records
  end

  def test_mysql_streams
    database, streaming = mock("mysql", :stream)
    Metacrunch::Db::Reader.new(Databases::FakeConnection.new(database), table: "books").each.to_a

    assert_equal [[:stream]], streaming.calls
  end

  def test_mysql_sets_net_write_timeout_first
    database, = mock("mysql", :stream)
    database.sqls
    Metacrunch::Db::Reader.new(Databases::FakeConnection.new(database), table: "books", idle_timeout: 120).each.to_a

    sqls = database.sqls

    assert_equal "SET SESSION net_write_timeout = 120", sqls.first
    assert_equal "SELECT * FROM `books`", sqls.last
  end

  def test_postgres_sets_the_idle_transaction_timeout_first
    database, = mock("postgres", :use_cursor)
    database.sqls
    Metacrunch::Db::Reader.new(Databases::FakeConnection.new(database), table: "books").each.to_a

    assert_equal ["SET idle_in_transaction_session_timeout = 3600000", "SELECT * FROM \"books\""], database.sqls
  end

  def test_sqlite_and_others_set_no_timeout
    database, = mock("oracle")
    database.sqls
    Metacrunch::Db::Reader.new(Databases::FakeConnection.new(database), table: "books").each.to_a

    assert_equal ['SELECT * FROM "BOOKS"'], database.sqls
  end

  def test_inspect_names_table_and_connection_without_password
    connection = Metacrunch::Db::Connection.new(url: "postgres://db/x", user: "etl", password: "secret")

    assert_equal "#<Metacrunch::Db::Reader table=books connection=#<Metacrunch::Db::Connection url=postgres://db/x " \
                 "user=etl password=[FILTERED]>>", Metacrunch::Db::Reader.new(connection, table: "books").inspect
  end

  def test_inspect_cuts_long_sql
    connection = Metacrunch::Db::Connection.new(url: "postgres://db/x")
    sql = "SELECT isbn, title, year, price, published, updated_at, available FROM books"

    assert_equal "#<Metacrunch::Db::Reader query=\"#{sql[0, 60]}...\" connection=#{connection.inspect}>",
                 Metacrunch::Db::Reader.new(connection, query: sql).inspect
    assert_includes Metacrunch::Db::Reader.new(connection, query: "SELECT  1").inspect, 'query="SELECT 1"'
    assert_includes Metacrunch::Db::Reader.new(connection, query: ->(db) { db[:books] }).inspect, "query=(callable)"
  end

  private

  def reader(**) = Metacrunch::Db::Reader.new(sqlite_connection, **)

  # A mock database of host whose datasets record the calls of the streaming methods; it yields one row.
  def mock(host, *methods)
    streaming = Databases::Streaming.new(*methods)
    database = Sequel.mock(host:, fetch: [{isbn: "1"}], columns: [:isbn])
    database.extend_datasets(streaming)
    [database, streaming]
  end

end
