# frozen_string_literal: true

require "test_helper"

# The reader against each database (see test/support/integration.rb).
module ReadingTests

  def test_reads_every_type_back
    name = table("types")
    database.create_table(name.to_sym) do
      Integer :id, primary_key: true
      String :title, size: 100
      Date :published
      Time :updated_at
      BigDecimal :price, size: [10, 2]
      TrueClass :available
      Integer :missing
    end
    updated_at = Time.new(2026, 10, 27, 12, 30, 15)
    database[name.to_sym].insert(id: 1, title: "Schuld und Sühne – Достоевский", published: Date.new(1866, 1, 1),
                                 updated_at:, price: BigDecimal("12.50"), available: true)
    record = reader(table: name).each.first

    assert_equal({"id" => 1, "title" => "Schuld und Sühne – Достоевский", "published" => Date.new(1866, 1, 1),
                  "price" => BigDecimal("12.50"), "available" => true, "missing" => nil},
                 record.except("updated_at"))
    assert_equal updated_at.to_i, record["updated_at"].to_i
  end

  def test_reads_more_rows_than_one_fetch
    name = create_books((1..2500).map { {isbn: format("%05d", it), title: "Book #{it}", year: 2000} })

    assert_equal 2500, reader(table: name).each.count
  end

  def test_reads_sql_with_values
    name = create_books([{isbn: "1", title: "A", year: 1990}, {isbn: "2", title: "B", year: 2010}])
    records = reader(query: "SELECT isbn FROM #{name} WHERE year > :year", values: {year: 2000}).each.to_a

    assert_equal [{"isbn" => "2"}], records
  end

  def test_reads_a_dataset
    name = create_books([{isbn: "1", title: "A", year: 1990}, {isbn: "2", title: "B", year: 2010}])
    records = reader(query: ->(db) { db[name.to_sym].where(year: 1990).select(:title) }).each.to_a

    assert_equal [{"title" => "A"}], records
  end

  def test_a_column_twice_is_refused
    name = create_books([{isbn: "1", title: "A", year: 1990}])
    query = "SELECT a.isbn, b.isbn FROM #{name} a JOIN #{name} b ON a.isbn = b.isbn"
    error = assert_raises(Metacrunch::InputError) { reader(query:).each.to_a }

    assert_equal "db query: the result has the column isbn twice; name the columns apart (AS)", error.message
  end

  def test_count_gives_progress
    name = create_books((1..4).map { {isbn: it.to_s, title: "B", year: 1} })
    source = reader(table: name, count: true)

    assert_equal([0.25, 0.5, 0.75, 1.0], source.each.map { source.progress })
  end

  # A reader stopped early holds no lock on the table: no cursor and no transaction stay open.
  def test_an_early_stop_leaves_no_transaction_open
    name = create_books((1..2500).map { {isbn: format("%05d", it), title: "Book", year: 2000} })
    source = Metacrunch::Db::Reader.new(connection, table: name)
    job = Metacrunch.job do
      source source
      sink Metacrunch::JsonLines::Writer.new(StringIO.new)
    end
    result = job.run(limit: 10, logger: Logger.new(StringIO.new))

    assert_equal 10, result.stats.read
    lock_timeout
    database.drop_table(name.to_sym)

    refute database.table_exists?(name.to_sym)
  end

  def test_the_idle_limit_is_set
    skip "SQLite has no idle limit" if type == :sqlite

    sql = if type == :mysql
      "SELECT @@session.net_write_timeout AS t"
    else
      "SELECT current_setting('idle_in_transaction_session_timeout') AS t"
    end
    record = reader(query: ->(db) { db.fetch(sql) }, idle_timeout: 120).each.first

    assert_equal(type == :mysql ? 120 : "2min", record.values.first)
  end

  def test_reads_a_qualified_table
    name = create_books([{isbn: "1", title: "A", year: 1}])

    assert_equal 1, reader(table: "#{schema}.#{name}").each.count
  end

  private

  def reader(**) = Metacrunch::Db::Reader.new(connection, **)

end

Integration.define("Reading", ReadingTests)
