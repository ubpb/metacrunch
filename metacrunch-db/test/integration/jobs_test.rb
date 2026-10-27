# frozen_string_literal: true

require "test_helper"

# Jobs that read and write each database (see test/support/integration.rb).
module JobTests

  # A failures sink that keeps the isbn and the class of the error.
  class Failures

    attr_reader :entries

    def initialize = @entries = []

    def write(record, ctx) = @entries << [record["isbn"], ctx.failure.error.class]

  end

  def test_copies_a_table_with_workers
    from = create_books((1..500).map { {isbn: format("%04d", it), title: "Book #{it}", year: 2000 + (it % 20)} })
    to = create_books(name: table("copy"))
    result = copy(from, to).run(workers: 2, logger: Logger.new(StringIO.new))

    assert_predicate result, :ok?
    assert_equal stored(from), stored(to)
  end

  def test_failures_go_to_the_failures_sink
    from = create_books([{isbn: "1", title: "A"}, {isbn: "2", title: "B"}, {isbn: "3", title: "C"}])
    to = create_books([{isbn: "2", title: "Taken"}], name: table("copy"))
    collected = Failures.new
    result = copy(from, to, action: :insert, collected:).run(logger: Logger.new(StringIO.new))

    assert_equal [:ok_with_failures, 2], [result.status, result.stats.written]
    assert_equal [["2", Sequel::UniqueConstraintViolation]], collected.entries
  end

  private

  def copy(from, to, action: :upsert, collected: nil)
    source = Metacrunch::Db::Reader.new(connection, table: from)
    writer = Metacrunch::Db::Writer.new(connection, table: to, action:, key: "isbn")
    Metacrunch.job do
      source source
      sink writer, batch: 100
      if collected
        failures collected
        on_failure :skip
      end
    end
  end

end

Integration.define("Jobs", JobTests)
