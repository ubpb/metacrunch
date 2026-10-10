# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class TestingTest < Minitest::Test

  # Fails if the job's own source or sinks are used.
  class Untouchable

    def each = raise("the job's source must not be read")

    def open(_context) = raise("the job's components must not be opened")

    def write(_record) = raise("the job's sinks must not be written")

  end

  def test_replaces_the_source_and_all_sinks
    result = Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [1, 0, 9])

    assert_equal [:ok_with_failures, [1]], [result.status, result.records]
    assert_equal([[9, "Too large"]], result.rejects.map { |record, rejection| [record, rejection.reason] })
    assert_equal([[0, "zero"]], result.errors.map { |record, failure| [record, failure.error.message] })
  end

  def test_converts_string_params
    result = Metacrunch::Testing.run(build_job, params: {limit: "0"}, source: [1])

    assert_equal([[1, "Too large"]], result.rejects.map { |record, rejection| [record, rejection.reason] })
  end

  def test_uses_the_jobs_source_when_none_is_given
    job = Metacrunch.job { source [1, 2] }

    assert_equal [1, 2], Metacrunch::Testing.run(job).records
  end

  def test_rejects_a_source_without_each
    assert_raises(ArgumentError) { Metacrunch::Testing.run(build_job, source: 42) }
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
