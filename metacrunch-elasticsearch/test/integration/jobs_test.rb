# frozen_string_literal: true

require "test_helper"

class JobsTest < Minitest::Test

  include Integration

  # Collects what a job writes.
  class Collector

    attr_reader :records

    def initialize
      @records = []
    end

    def write(record) = @records << record

  end

  BOOKS = [{"id" => "1", "year" => "1851"}, {"id" => "2", "year" => "unknown"}, {"id" => "3", "year" => "1815"},
           {"id" => "4", "year" => "1847"}, {"id" => "5", "year" => "1813"}].freeze

  def setup
    super
    create_index
  end

  def test_loads_records_and_sends_refused_ones_to_the_failures_sink
    [nil, 2].each do |workers|
      failed = Collector.new
      result = load_job(failed).run(workers:, logger: Logger.new(nil))

      assert_equal [:ok_with_failures, 4, ["2"]], [result.status, result.stats.written, failed.records.map { it["id"] }]
    end
    assert_equal ["1", "3", "4", "5"], stored.keys.sort
  end

  def test_a_refused_record_aborts_the_run_by_default
    es = connection
    index = @index
    result = Metacrunch.job do
      source BOOKS
      sink Metacrunch::Elasticsearch::Writer.new(es, index:, id: "id"), batch: 10
    end.run(logger: Logger.new(nil))

    assert_equal [:aborted, "sink"], [result.status, result.error.step]
  end

  def test_reads_an_index_with_and_without_workers
    index_documents(BOOKS.reject { it["id"] == "2" })
    es = connection
    index = @index
    outputs = [nil, 2].map do |workers|
      collected = Collector.new
      Metacrunch.job do
        source Metacrunch::Elasticsearch::Reader.new(es, index:, size: 2)
        map { it.merge("year" => it["year"].to_i) }
        sink collected
      end.run(workers:, logger: Logger.new(nil))
      collected.records.sort_by { it["id"] }
    end

    assert_equal [[1851, 1815, 1847, 1813]], outputs.map { |records| records.map { it["year"] } }.uniq
  end

  private

  def load_job(failed)
    es = connection
    index = @index
    Metacrunch.job do
      source BOOKS
      sink Metacrunch::Elasticsearch::Writer.new(es, index:, id: "id"), batch: 2
      failures failed
      on_failure :skip
    end
  end

end
