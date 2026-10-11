# frozen_string_literal: true

# Tests the catalog example without files: Metacrunch::Testing.run replaces
# the source by the given records and every sink by a memory sink.
#
#   bundle exec ruby -Ilib examples/test/catalog_test.rb

require "minitest/autorun"
require "metacrunch"
require "metacrunch/testing"

class CatalogTest < Minitest::Test

  JOB = Metacrunch.load_job(File.expand_path("../catalog.rb", __dir__))
  PARAMS = {output: "unused", input: ["unused.json"]}.freeze

  def test_writes_one_record_per_isbn
    result = run_job([{"_id" => "1", "public" => true, "title" => "Ruby", "year" => 2020, "isbns" => ["1", "2"]}])

    assert_equal(["1", "2"], result.records.map { it["isbn"] })
  end

  def test_rejects_records_that_are_not_public
    result = run_job([{"_id" => "2", "public" => false, "title" => "Secret", "year" => 2021}])

    assert_equal(["Not public"], result.rejects.map { |_record, rejection| rejection.reason })
  end

  def test_marks_records_without_a_title
    result = run_job([{"_id" => "3", "public" => true, "title" => nil, "year" => 2001}])

    assert_equal({"No title" => 1}, result.stats.marked)
  end

  def test_gives_the_same_records_with_workers
    records = Array.new(10) { {"_id" => it.to_s, "public" => true, "title" => "T#{it}", "year" => 2000 + it} }

    assert_equal run_job(records).records, run_job(records, workers: 2).records
  end

  private

  def run_job(records, workers: nil)
    Metacrunch::Testing.run(JOB, params: PARAMS, source: records, workers:)
  end

end
