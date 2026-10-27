# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

# The reader and the writer in jobs: inline, with workers, with the failure policy and in Metacrunch::Testing.
class JobsTest < Minitest::Test

  include Databases

  # A failures sink that keeps the isbn and the class of the error.
  class Failures

    attr_reader :entries

    def initialize = @entries = []

    def write(record, ctx) = @entries << [record["isbn"], ctx.failure.error.class]

  end

  BOOKS = [{isbn: "1", title: "A", year: 2001}, {isbn: "2", title: "B", year: 2002},
           {isbn: "3", title: "C", year: 2003}].freeze

  def setup
    super
    create_books(sqlite("source"), BOOKS)
    create_books(sqlite("target"))
  end

  def test_a_job_copies_a_table
    result = copy_job.run(logger: Logger.new(StringIO.new))

    assert_predicate result, :ok?
    assert_equal BOOKS.map { it[:isbn] }, sqlite("target")[:books].order(:isbn).select_map(:isbn)
    assert_equal 3, result.stats.written
  end

  def test_a_job_copies_with_workers
    result = copy_job.run(workers: 2, logger: Logger.new(StringIO.new))

    assert_predicate result, :ok?
    assert_equal 3, sqlite("target")[:books].count
  end

  def test_a_limit_stops_the_reader
    result = copy_job.run(limit: 2, logger: Logger.new(StringIO.new))

    assert_equal 2, result.stats.written
  end

  def test_failures_reach_the_failures_sink_with_skip
    sqlite("target")[:books].insert(isbn: "2", title: "Taken")
    collected = Failures.new
    source = sqlite_connection("source")
    target = sqlite_connection("target")
    job = Metacrunch.job do
      source Metacrunch::Db::Reader.new(source, table: "books")
      sink Metacrunch::Db::Writer.new(target, table: "books"), batch: 10
      failures collected
      on_failure :skip
    end
    result = job.run(logger: Logger.new(StringIO.new))

    assert_equal :ok_with_failures, result.status
    assert_equal [["2", Sequel::UniqueConstraintViolation]], collected.entries
    assert_equal 2, result.stats.written
  end

  def test_testing_run_opens_no_database
    unreachable = Metacrunch::Db::Connection.new(url: "postgres://nowhere.invalid/catalog")
    job = Metacrunch.job do
      sink Metacrunch::Db::Writer.new(unreachable, table: "books"), batch: 10
    end
    result = Metacrunch::Testing.run(job, source: [{"isbn" => "1"}])

    assert_equal [{"isbn" => "1"}], result.records
  end

  private

  def copy_job
    source = sqlite_connection("source")
    target = sqlite_connection("target")
    Metacrunch.job do
      source Metacrunch::Db::Reader.new(source, table: "books")
      sink Metacrunch::Db::Writer.new(target, table: "books", action: :upsert, key: "isbn"), batch: 2
    end
  end

end
