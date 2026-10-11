# frozen_string_literal: true

require "test_helper"

class JobTest < Minitest::Test

  include ForkVariant::NoWorkerLeft

  SILENT = Logger.new(nil)

  def test_run_binds_cli_arguments_and_returns_the_result
    target = CollectingSink.new
    job = Metacrunch.job do
      params do
        param :factor, Integer, default: 1
        args :numbers
      end
      source params.numbers.map(&:to_i)
      map { it * params.factor }
      sink target
    end
    result = job.run(["--factor", "3", "1", "2"], logger: SILENT)

    assert_equal :ok, result.status
    assert_equal [3, 6], target.records
  end

  def test_run_with_workers_gives_the_same_records
    target = CollectingSink.new
    job = Metacrunch.job do
      source [1, 2, 3, 4]
      map { it * 2 }
      sink target
    end
    result = job.run([], logger: SILENT, workers: 2)

    assert_equal [:ok, [2, 4, 6, 8]], [result.status, target.records]
  end

  def test_each_run_builds_a_fresh_pipeline
    built = 0
    job = Metacrunch.job do
      built += 1
      source []
    end
    2.times { job.run([], logger: SILENT) }

    assert_equal 2, built
  end

  def test_run_raises_param_errors
    job = Metacrunch.job do
      params { param :index, String, required: true }
      source []
    end

    assert_raises(Metacrunch::ParamError) { job.run([], env: {}, logger: SILENT) }
  end

  def test_describe_returns_the_params_without_building_components
    job = Metacrunch.job do
      params { param :index, String, required: true }
      source raise("must not be built")
    end

    assert_equal [:index], job.describe.definitions.keys
  end

  def test_run_accepts_a_limit
    job = Metacrunch.job { source [1, 2, 3] }

    assert_equal 2, job.run([], logger: Logger.new(nil), limit: 2).stats.read
  end

  def test_a_job_needs_a_recipe
    assert_raises(ArgumentError) { Metacrunch::Job.new("empty") }
  end

end
