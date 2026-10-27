# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Databases

  def setup
    super
    @books = create_books(sqlite)
    @books.alter_table(:books) { add_index :title, unique: true, name: :books_title }
  end

  def test_action_must_be_known_or_callable
    error = assert_raises(ArgumentError) { writer(action: :index) }

    assert_equal "action must be one of :insert, :upsert, :update, :delete or a callable, got :index", error.message
  end

  def test_key_is_required_but_for_insert
    [:upsert, :update, :delete].each do |action|
      error = assert_raises(ArgumentError) { writer(action:) }

      assert_equal "action #{action.inspect} needs key:", error.message
    end
  end

  def test_a_callable_action_needs_a_key
    error = assert_raises(ArgumentError) { writer(action: ->(_) { :insert }) }

    assert_equal "a callable action needs key:", error.message
  end

  def test_key_takes_a_column_or_columns
    assert_equal "#<Metacrunch::Db::Writer table=books action=update key=isbn,year " \
                 "connection=#{sqlite_connection.inspect}>", writer(action: :update, key: ["isbn", :year]).inspect
    [[], "", ["a", 1], 42].each do |key|
      error = assert_raises(ArgumentError) { writer(action: :update, key:) }

      assert_equal "key must be a column or an Array of columns, got #{key.inspect}", error.message
    end
  end

  def test_max_bytes_must_be_positive
    error = assert_raises(ArgumentError) { writer(max_bytes: 0) }

    assert_equal "max_bytes must be a positive Integer, got 0", error.message
  end

  def test_open_refuses_a_missing_table
    error = assert_raises(Metacrunch::OutputError) { writer(table: "nope").open(context) }

    assert_equal "db nope: no such table", error.message
  end

  def test_open_refuses_a_key_that_is_no_column
    error = assert_raises(Metacrunch::OutputError) { writer(action: :update, key: ["isbn", "ean"]).open(context) }

    assert_equal "db books: key ean is no column of books", error.message
  end

  def test_open_refuses_upsert_by_a_key_that_is_not_unique
    error = assert_raises(Metacrunch::OutputError) { writer(action: :upsert, key: "year").open(context) }

    assert_equal "db books: key year is neither the primary key nor a unique index of books", error.message
  end

  def test_open_takes_upsert_by_the_primary_key_or_a_unique_index
    writer(action: :upsert, key: "isbn").open(context)
    writer(action: :upsert, key: "title").open(context)
  end

  def test_open_refuses_upsert_without_support
    error = assert_raises(Metacrunch::OutputError) { mocked("oracle", action: :upsert, key: "isbn").open(context) }

    assert_equal "db books: upsert needs PostgreSQL, SQLite, MySQL or MariaDB; this is oracle", error.message
  end

  def test_open_takes_upsert_when_the_adapter_cannot_read_indexes
    sink = mocked("postgres", action: :upsert, key: "title") do |database|
      database.define_singleton_method(:supports_index_parsing?) { false }
    end

    assert_kind_of Sequel::Database, sink.open(context)
  end

  # table_exists? selects from the table, which a user who may only insert must not.
  def test_open_takes_a_table_it_cannot_select_from_but_whose_schema_it_reads
    sink = mocked("postgres") { |database| database.define_singleton_method(:table_exists?) { |*| false } }

    assert_kind_of Sequel::Database, sink.open(context)
  end

  def test_open_refuses_a_table_it_neither_selects_from_nor_reads_the_schema_of
    sink = mocked("postgres") do |database|
      database.define_singleton_method(:table_exists?) { |*| false }
      database.define_singleton_method(:schema) { |*| raise Sequel::Error, "no such table" }
    end
    error = assert_raises(Metacrunch::OutputError) { sink.open(context) }

    assert_equal "db books: no such table", error.message
  end

  def test_open_takes_upsert_when_the_adapter_cannot_read_the_schema
    sink = mocked("postgres", action: :upsert, key: "isbn") do |database|
      database.define_singleton_method(:supports_schema_parsing?) { false }
    end

    assert_kind_of Sequel::Database, sink.open(context)
  end

  def test_open_turns_sequel_errors_into_output_errors
    sink = mocked("postgres") { |database| database.define_singleton_method(:schema) { |*| raise Sequel::Error, "x" } }
    error = assert_raises(Metacrunch::OutputError) { sink.open(context) }

    assert_equal "db books: x", error.message
  end

  def test_open_skips_checks_without_schema_parsing
    database = Sequel.mock
    database.define_singleton_method(:supports_schema_parsing?) { false }
    sink = Metacrunch::Db::Writer.new(Databases::FakeConnection.new(database), table: "books")
    sink.open(context)
    sink.write_batch([{"anything" => 1}])

    assert_equal ["INSERT INTO books (anything) VALUES (1)"], database.sqls.grep(/INSERT/)
  end

  def test_open_connects_once
    connection = Databases::FakeConnection.new(sqlite)
    sink = Metacrunch::Db::Writer.new(connection, table: "books")
    sink.open(context)
    sink.write_batch([{"isbn" => "1", "title" => "A"}])

    assert_equal 1, connection.connects
  end

  def test_a_failed_connect_is_an_output_error
    connection = Metacrunch::Db::Connection.new(url: "sqlite://#{@dir}/missing/x.db")
    error = assert_raises(Metacrunch::OutputError) { Metacrunch::Db::Writer.new(connection, table: "books").open(context) }

    assert_match(%r{\Adb books: sqlite://.*/missing/x.db: }, error.message)
  end

  def test_inserts_a_batch
    writer.write_batch([{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "B", "year" => 2001}])

    assert_equal [["1", "A", nil], ["2", "B", 2001]], stored(:isbn, :title, :year)
  end

  def test_write_batch_without_open_connects
    sink = Metacrunch::Db::Writer.new(sqlite_connection, table: "books")
    sink.write_batch([{"isbn" => "1", "title" => "A"}])

    assert_equal [["1"]], stored(:isbn)
  end

  def test_upserts
    @books[:books].insert(isbn: "1", title: "Old", year: 1999)
    writer(action: :upsert,
           key: "isbn").write_batch([{"isbn" => "1", "title" => "New"}, {"isbn" => "2", "title" => "B"}])

    assert_equal [["1", "New", 1999], ["2", "B", nil]], stored(:isbn, :title, :year)
  end

  # Records from JSON leave out absent fields: one statement per set of columns, not per record.
  def test_records_with_and_without_a_column_share_statements_by_key
    log = StringIO.new
    sink = writer(connection: sqlite_connection(loggers: [Logger.new(log)]), action: :upsert, key: "isbn")
    sink.write_batch((1..10).map { {"isbn" => it.to_s, "title" => "T#{it}"}.merge(it.even? ? {"year" => it} : {}) })

    assert_equal [2, 10], [log.string.scan("INSERT INTO").size, @books[:books].count]
  end

  def test_inserts_without_a_key_that_share_few_statements_log_a_hint_once
    log = StringIO.new
    sink = writer
    sink.open(context(log))
    2.times do |batch|
      books = (1..20).map { {"isbn" => "#{batch}-#{it}", "title" => "T#{batch}-#{it}"} }
      sink.write_batch(books.each_with_index.map { |book, i| i.even? ? book.merge("year" => i) : book })
    end

    assert_equal 1, log.string.scan("db books: records with different columns share no statement; give the writer " \
                                    "key: or every record the same columns").size
  end

  def test_inserts_of_the_same_columns_log_no_hint
    log = StringIO.new
    sink = writer
    sink.open(context(log))
    sink.write_batch((1..20).map { {"isbn" => it.to_s, "title" => "T#{it}"} })

    refute_includes log.string, "share no statement"
  end

  def test_upsert_keeps_the_last_record_of_a_key
    writer(action: :upsert, key: "isbn").write_batch([{"isbn" => "1", "title" => "A"}, {"isbn" => "1", "title" => "B"}])

    assert_equal [["1", "B"]], stored(:isbn, :title)
  end

  def test_updates
    @books[:books].insert(isbn: "1", title: "Old", year: 1999)
    writer(action: :update, key: "isbn").write_batch([{"isbn" => "1", "year" => 2000}])

    assert_equal [["1", "Old", 2000]], stored(:isbn, :title, :year)
  end

  def test_deletes_and_a_missing_row_counts_as_written
    @books[:books].multi_insert([{isbn: "1", title: "A"}, {isbn: "2", title: "B"}])
    writer(action: :delete, key: "isbn").write_batch([{"isbn" => "1", "title" => "ignored"}, {"isbn" => "9"}])

    assert_equal [["2"]], stored(:isbn)
  end

  def test_a_callable_chooses_the_action_per_record
    @books[:books].insert(isbn: "1", title: "A")
    action = ->(book) { book["deleted"] ? :delete : :upsert }
    writer(action:, key: "isbn").write_batch([{"isbn" => "1", "deleted" => true}, {"isbn" => "2", "title" => "B"}])

    assert_equal [["2"]], stored(:isbn)
  end

  def test_the_order_of_a_batch_holds
    action = ->(book) { book.size == 1 ? :delete : :upsert }
    writer(action:, key: "isbn").write_batch([{"isbn" => "1", "title" => "A"}, {"isbn" => "1"},
                                              {"isbn" => "2", "title" => "B"}])

    assert_equal [["2"]], stored(:isbn)
  end

  def test_write_logs_the_batch_hint_once
    log = StringIO.new
    sink = writer
    sink.open(context(log))
    sink.write({"isbn" => "1", "title" => "A"})
    sink.write({"isbn" => "2", "title" => "B"})

    assert_equal 1, log.string.scan("db books: writing one record per transaction; use `sink ..., batch: 1000`").size
    refute_includes log.string, "share no statement"
    assert_equal 2, @books[:books].count
  end

  def test_an_empty_batch_writes_nothing
    assert_nil writer.write_batch([])
  end

  def test_refused_rows_are_failures_and_the_others_are_written
    @books[:books].insert(isbn: "2", title: "Taken")
    books = [{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "B"}, {"isbn" => "3", "title" => "C"}]
    error = assert_raises(Metacrunch::SinkFailures) { writer.write_batch(books) }

    assert_equal({1 => Sequel::UniqueConstraintViolation}, error.failed.transform_values(&:class))
    assert_equal [["1", "A"], ["2", "Taken"], ["3", "C"]], stored(:isbn, :title)
  end

  def test_record_checks_are_failures
    error = assert_raises(Metacrunch::SinkFailures) do
      writer.write_batch([{"isbn" => "1", "title" => "A"}, "no hash", {"isbn" => "3", "titel" => "C"}])
    end

    assert_equal({1 => "record is a String, not a Hash", 2 => "books has no column titel"},
                 error.failed.transform_values(&:message))
    assert_equal [["1"]], stored(:isbn)
  end

  def test_a_batch_of_failed_records_raises_them
    error = assert_raises(Metacrunch::SinkFailures) { writer.write_batch(["no hash"]) }

    assert_equal [0], error.failed.keys
  end

  def test_a_bad_action_of_a_callable_is_a_failure
    error = assert_raises(Metacrunch::SinkFailures) do
      writer(action: ->(_) { :index }, key: "isbn").write_batch([{"isbn" => "1"}])
    end

    assert_equal "action must be one of :insert, :upsert, :update, :delete, got :index", error.failed[0].message
  end

  def test_update_without_a_row_is_a_failure
    error = assert_raises(Metacrunch::SinkFailures) do
      writer(action: :update, key: ["isbn", "year"]).write_batch([{"isbn" => "x", "year" => 1, "title" => "A"}])
    end

    assert_equal "no row with isbn = \"x\", year = 1 in books", error.failed[0].message
  end

  def test_an_upsert_retried_alone_keeps_the_order_of_its_key
    @books[:books].insert(isbn: "9", title: "Taken")
    error = assert_raises(Metacrunch::SinkFailures) do
      writer(action: :upsert, key: "isbn").write_batch([{"isbn" => "1", "title" => "A"},
                                                        {"isbn" => "1", "title" => "Taken"}])
    end

    assert_equal [1], error.failed.keys
    assert_equal [["1", "A"], ["9", "Taken"]], stored(:isbn, :title)
  end

  # ON DUPLICATE KEY UPDATE of MySQL would insert a duplicate for a key that is not unique; ON CONFLICT would refuse
  # every record.
  def test_a_callable_upsert_by_a_key_that_is_not_unique_stops_the_run
    @books[:books].insert(isbn: "1", title: "Old", year: 2000)
    sink = writer(action: ->(_) { :upsert }, key: "year")
    sink.open(context)
    error = assert_raises(Metacrunch::OutputError) { sink.write_batch([{"isbn" => "2", "title" => "New", "year" => 2000}]) }

    assert_equal "db books: key year is neither the primary key nor a unique index of books", error.message
    assert_equal [["1"]], stored(:isbn)
  end

  def test_a_callable_upsert_by_a_unique_key_writes
    sink = writer(action: ->(_) { :upsert }, key: "isbn")
    sink.open(context)
    2.times { |i| sink.write_batch([{"isbn" => i.to_s, "title" => "T#{i}"}]) }

    assert_equal [["0"], ["1"]], stored(:isbn)
  end

  def test_a_callable_upsert_without_support_stops_the_run
    sink = mocked("oracle", action: ->(_) { :upsert }, key: "isbn")
    sink.open(context)
    error = assert_raises(Metacrunch::OutputError) { sink.write_batch([{"isbn" => "1"}]) }

    assert_equal "db books: upsert needs PostgreSQL, SQLite, MySQL or MariaDB; this is oracle", error.message
  end

  def test_a_fatal_error_rolls_back_the_batch
    fail_on_import(2, Sequel::DatabaseDisconnectError, "connection lost")
    error = assert_raises(Metacrunch::OutputError) do
      writer(connection: Databases::FakeConnection.new(@books))
        .write_batch([{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "B", "year" => 1}])
    end

    assert_equal ["db books: connection lost", Sequel::DatabaseDisconnectError], [error.message, error.cause.class]
    assert_empty stored(:isbn)
  end

  def test_a_fatal_error_while_retrying_alone_stops_the_run
    @books[:books].insert(isbn: "2", title: "Taken")
    fail_on_import(3, Sequel::SerializationFailure, "deadlock")
    error = assert_raises(Metacrunch::OutputError) do
      writer(connection: Databases::FakeConnection.new(@books))
        .write_batch([{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "Taken"}])
    end

    assert_equal "db books: deadlock", error.message
  end

  # A database that refuses every statement (no right to write, read-only, full) is no refusal of the records.
  def test_an_error_that_is_not_about_a_record_stops_the_run
    connection = sqlite_connection(readonly: true)
    error = assert_raises(Metacrunch::OutputError) do
      writer(connection:).write_batch([{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "B"}])
    end

    assert_match(/\Adb books: .*readonly database/, error.message)
    assert_empty stored(:isbn)
  end

  def test_a_sequel_error_that_is_no_database_error_stops_the_run
    fail_on_import(1, Sequel::Error, "invalid")
    error = assert_raises(Metacrunch::OutputError) do
      writer(connection: Databases::FakeConnection.new(@books)).write_batch([{"isbn" => "1", "title" => "A"}])
    end

    assert_equal "db books: invalid", error.message
  end

  def test_close_disconnects
    connection = Databases::FakeConnection.new(sqlite_connection.connect)
    sink = Metacrunch::Db::Writer.new(connection, table: "books")
    sink.open(context)
    sink.write_batch([{"isbn" => "1", "title" => "A"}])
    sink.close

    assert_equal 0, connection.connect.pool.size
  end

  def test_close_without_open_does_nothing
    assert_nil writer.close
  end

  def test_inspect_of_an_insert_names_no_key
    assert_equal "#<Metacrunch::Db::Writer table=books action=insert connection=#{sqlite_connection.inspect}>",
                 writer.inspect
  end

  def test_inspect_hides_the_password
    connection = Metacrunch::Db::Connection.new(url: "postgres://db/x", user: "etl", password: "secret")

    assert_equal "#<Metacrunch::Db::Writer table=books action=(callable) key=isbn connection=#<Metacrunch::Db::" \
                 "Connection url=postgres://db/x user=etl password=[FILTERED]>>",
                 Metacrunch::Db::Writer.new(connection, table: "books", action: ->(_) {}, key: "isbn").inspect
  end

  private

  def writer(connection: sqlite_connection, table: "books", **) = Metacrunch::Db::Writer.new(connection, table:, **)

  # A writer to a mock database of host with the columns isbn and title; the block may change the database.
  def mocked(host, **)
    database = Sequel.mock(host:)
    database.define_singleton_method(:schema) { |*| [[:isbn, {primary_key: true}], [:title, {}]] }
    yield database if block_given?
    Metacrunch::Db::Writer.new(Databases::FakeConnection.new(database), table: "books", **)
  end

  # The test database's import raises error with message on its nth call.
  def fail_on_import(nth, error, message)
    calls = 0
    @books.extend_datasets(Module.new do
      define_method(:import) do |*args|
        calls += 1
        raise error, message if calls == nth

        super(*args)
      end
    end)
  end

  def stored(*columns) = @books[:books].order(:isbn).select_map(columns)

end
