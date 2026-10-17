# frozen_string_literal: true

require "test_helper"

class JobTest < Minitest::Test

  include ForkVariant::NoWorkerLeft
  include CredentialsHelper

  SILENT = Logger.new(nil)
  SCALE = "Metacrunch.transform(\"scale\") { map { it * 2 } }\n"

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

  def test_names_follow_the_name_rules
    error = assert_raises(ArgumentError) { Metacrunch.job("Catalog") { source [] } }

    assert_match(/invalid job name "Catalog"/, error.message)
  end

  def test_jobs_have_a_description
    job = Metacrunch.job("catalog", desc: "Export the catalog") { source [] }

    assert_equal ["catalog", "Export the catalog"], [job.name, job.desc]
  end

  def test_jobs_may_stay_unnamed
    job = Metacrunch.job { source [] }

    assert_nil job.name
    assert_nil job.desc
  end

  def test_run_resolves_names_in_the_given_project
    in_tmpdir do |root|
      write_project(root)
      target = CollectingSink.new
      job = Metacrunch.job do
        source [1]
        use "scale"
        sink target
      end
      job.run([], logger: SILENT, project: Metacrunch.load_project(root))

      assert_equal [2], target.records
    end
  end

  def test_run_finds_the_project_of_the_working_directory_when_a_name_needs_it
    in_tmpdir do |root|
      write_project(root)
      FileUtils.mkdir_p(File.join(root, "sub"))
      job = Metacrunch.job { source [1]; use "scale" }
      result = Dir.chdir(File.join(root, "sub")) { job.run([], logger: SILENT) }

      assert_equal [:ok, ["scale/map#1"]], [result.status, result.stats.steps.keys]
    end
  end

  def test_run_without_a_project_names_the_missing_metacrunchfile
    in_tmpdir do |dir|
      job = Metacrunch.job { source [1]; use "scale" }
      error = Dir.chdir(dir) { assert_raises(Metacrunch::ProjectError) { job.run([], logger: SILENT) } }

      assert_equal "unknown job, transform, command or file: scale (no Metacrunchfile found)", error.message
    end
  end

  def test_run_uses_transforms_by_path_without_a_project
    in_tmpdir do |dir|
      path = write_file(dir, "scale.rb", "# frozen_string_literal: true\n\n#{SCALE}")
      target = CollectingSink.new
      job = Metacrunch.job do
        source [1]
        use path
        sink target
      end
      job.run([], logger: SILENT)

      assert_equal [2], target.records
    end
  end

  private

  def write_project(root)
    write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nMetacrunch.load_files \"transforms/*.rb\"\n")
    write_file(root, "transforms/scale.rb", "# frozen_string_literal: true\n\n#{SCALE}")
  end

end
