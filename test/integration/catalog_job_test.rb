# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"
require "metacrunch/cli"
require "metacrunch/testing"

class CatalogJobTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  JOB = File.join(ROOT, "test", "fixtures", "jobs", "catalog.rb")
  INPUT = File.join(ROOT, "test", "fixtures", "catalog.json")

  EXPECTED_FILES = {
    "records.jsonl" => [
      {"id" => "1", "title" => "Ruby", "year" => 2020, "isbn" => "978-1"},
      {"id" => "1", "title" => "Ruby", "year" => 2020, "isbn" => "978-2"},
      {"id" => "4", "title" => nil, "year" => 2001}
    ],
    "rejects.jsonl" => [{"_id" => "2", "public" => false, "title" => "Secret", "year" => 2021, "isbns" => []}],
    "errors.jsonl" => [{"_id" => "5", "public" => true, "title" => "No ISBN field", "year" => 2005}]
  }.freeze

  SUMMARY = Regexp.new(Regexp.escape(
                         "ok_with_failures: read 5, written 3, filtered 1, rejected 1 (Not public: 1), " \
                         "marked 1 (No title: 1), failed 1 (KeyError: 1)"
                       ))

  # Runs from a temporary working directory with a relative --output, so
  # the files must land in that directory (the CLI must not chdir).
  def test_runs_through_the_executable_relative_to_the_working_directory
    Dir.mktmpdir do |dir|
      exe = File.join(ROOT, "exe", "metacrunch")
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I", File.join(ROOT, "lib"), exe, JOB, "--output", ".", INPUT, chdir: dir
      )

      assert_equal 3, status.exitstatus, stderr
      assert_equal EXPECTED_FILES, read_outputs(dir)
      assert_match SUMMARY, stderr
    end
  end

  def test_runs_in_tests_without_files
    records = JSON.parse(File.read(INPUT))
    result = Metacrunch::Testing.run(
      Metacrunch.load_job(JOB), params: {output: "unused", input: ["unused.json"]}, source: records
    )

    assert_equal [:ok_with_failures, EXPECTED_FILES["records.jsonl"]], [result.status, result.records]
    assert_equal([["2", "Not public"]], result.rejects.map { |record, rejection| [record["_id"], rejection.reason] })
    assert_equal([["5", "KeyError"]], result.errors.map { |record, failure| [record["_id"], failure.error.class.name] })
  end

  def test_min_year_can_come_from_the_environment
    Dir.mktmpdir do |dir|
      code = nil
      capture_io do
        cli = Metacrunch::Cli.new(env: {"CATALOG_MIN_YEAR" => "1800"})
        code = cli.run([JOB, "--output", dir, INPUT])
      end

      assert_equal 3, code
      assert_equal 4, File.readlines(File.join(dir, "records.jsonl")).size
    end
  end

  private

  def read_outputs(dir)
    ["records.jsonl", "rejects.jsonl", "errors.jsonl"].to_h do |name|
      [name, File.readlines(File.join(dir, name)).map { |line| JSON.parse(line) }]
    end
  end

end
