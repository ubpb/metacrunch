# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class TestingTest < Minitest::Test

  include ForkVariant::NoWorkerLeft
  include CredentialsHelper

  # Fails if the job's own source or sinks are used.
  class Untouchable

    def each = raise("the job's source must not be read")

    def open(_context) = raise("the job's components must not be opened")

    def write(_record) = raise("the job's sinks must not be written")

  end

  SCALE = "# frozen_string_literal: true\n\nMetacrunch.transform(\"scale\") { map { it * 2 } }\n"

  def test_replaces_the_source_and_all_sinks
    result = Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [1, 0, 9])

    assert_equal [:ok_with_failures, [1]], [result.status, result.records]
    assert_equal([[9, "Too large"]], result.rejects.map { |record, rejection| [record, rejection.reason] })
    assert_equal([[0, "zero"]], result.errors.map { |record, failure| [record, failure.error.message] })
  end

  def test_runs_jobs_with_workers
    result = Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [1, 0, 9], workers: 2)

    assert_equal [:ok_with_failures, [1]], [result.status, result.records]
    assert_equal([[0, "zero"]], result.errors.map { |record, failure| [record, failure.error.message] })
  end

  def test_jobs_without_a_source_need_one
    job = Metacrunch.job { map { it * 2 } }
    error = assert_raises(ArgumentError) { Metacrunch::Testing.run(job) }

    assert_equal "the job has no source; pass source:", error.message
    assert_equal [2], Metacrunch::Testing.run(job, source: [1]).records
  end

  def test_converts_string_params
    result = Metacrunch::Testing.run(build_job, params: {limit: "0"}, source: [1])

    assert_equal([[1, "Too large"]], result.rejects.map { |record, rejection| [record, rejection.reason] })
  end

  def test_uses_the_jobs_source_when_none_is_given
    job = Metacrunch.job { source [1, 2] }

    assert_equal [1, 2], Metacrunch::Testing.run(job).records
  end

  def test_jobs_without_a_sink_report_nothing_written
    seen = []
    job = Metacrunch.job do
      source [1, 2]
      after { |result| seen << result.stats.written }
    end
    result = Metacrunch::Testing.run(job)

    assert_equal [[1, 2], 0], [result.records, result.stats.written]
    assert_equal [0], seen
  end

  def test_rejects_a_source_without_each
    assert_raises(ArgumentError) { Metacrunch::Testing.run(build_job, source: 42) }
  end

  def test_runs_a_transform_with_a_source
    transform = Metacrunch.transform do
      params { param :factor, Integer, default: 2 }

      map { it * params.factor }
    end
    error = assert_raises(ArgumentError) { Metacrunch::Testing.run(transform) }

    assert_equal [3], Metacrunch::Testing.run(transform, params: {factor: 3}, source: [1]).records
    assert_equal "a transform has no source; pass source:", error.message
  end

  def test_resolves_names_in_the_given_project
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nMetacrunch.load_files \"transforms/*.rb\"\n")
      write_file(root, "transforms/scale.rb", SCALE)
      job = Metacrunch.job { source [1]; use "scale" }
      result = Metacrunch::Testing.run(job, project: Metacrunch.load_project(root))

      assert_equal [[2], ["scale/map#1"]], [result.records, result.stats.steps.keys]
    end
  end

  def test_resolves_names_in_the_project_of_the_working_directory
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nMetacrunch.load_files \"transforms/*.rb\"\n")
      write_file(root, "transforms/scale.rb", SCALE)
      job = Metacrunch.job { source [1]; use "scale" }
      result = Dir.chdir(root) { Metacrunch::Testing.run(job) }

      assert_equal [2], result.records
    end
  end

  def test_transforms_get_no_environment
    transform = Metacrunch.transform("env") do
      params { param :factor, Integer, env: "METACRUNCH_TEST_FACTOR", default: 2 }

      map { it * params.factor }
    end
    job = Metacrunch.job { source [1]; use transform }
    ENV["METACRUNCH_TEST_FACTOR"] = "7"

    assert_equal [2], Metacrunch::Testing.run(job).records
  ensure
    ENV.delete("METACRUNCH_TEST_FACTOR")
  end

  def test_params_are_bound_like_use_but_without_the_environment
    job = Metacrunch.job do
      params do
        param :lang, String, env: "METACRUNCH_TEST_LANG", default: "de"
        param :path, String
      end
      source [1]
      map { [params.lang, params.path] }
    end
    ENV["METACRUNCH_TEST_LANG"] = "en"
    result = Metacrunch::Testing.run(job, params: {path: Pathname("a/b")})

    assert_equal [["de", "a/b"]], result.records
  ensure
    ENV.delete("METACRUNCH_TEST_LANG")
  end

  def test_unknown_params_raise_argument_errors
    error = assert_raises(ArgumentError) { Metacrunch::Testing.run(build_job, params: {limt: 5}, source: []) }

    assert_match(/\Aunknown parameter :limt \(known: /, error.message)
  end

  private

  def build_job
    Metacrunch.job do
      params { param :limit, Integer, default: 100 }
      source Untouchable.new
      reject("Too large") { it > params.limit }
      map { it.zero? ? raise(ArgumentError, "zero") : it }
      sink Untouchable.new
      rejects Untouchable.new
      errors Untouchable.new
      on_error :skip
    end
  end

end
