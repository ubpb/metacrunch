# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class RootTest < Minitest::Test

  include CredentialsHelper
  include RootFixtures
  include Override
  include ForkVariant::NoWorkerLeft

  SILENT = Logger.new(nil)

  def test_root_reaches_params_statements_hooks_and_steps
    in_tmpdir do |dir|
      log = StringIO.new
      result = Metacrunch::Testing.run(write_project(dir), "rooted", logger: Logger.new(log))

      assert_equal ["a@#{File.basename(dir)}"], result.records
      assert_includes log.string, "root #{dir}"
    end
  end

  def test_root_works_in_workers
    in_tmpdir do |dir|
      result = Metacrunch::Testing.run(write_project(dir), "rooted", workers: 2)

      assert_equal ["a@#{File.basename(dir)}"], result.records
    end
  end

  def test_a_transform_gets_the_root_of_the_job_that_uses_it
    in_tmpdir do |dir|
      assert_equal ["x:#{File.basename(dir)}"], Metacrunch::Testing.run(write_project(dir), "labeled").records
    end
  end

  def test_job_run_takes_the_root_from_project_or_working_directory
    in_tmpdir do |dir|
      project = write_project(dir)
      job = project.fetch("rooted")
      FileUtils.mkdir_p(File.join(dir, "sub"))
      results = [job.run(logger: SILENT, project:), Dir.chdir(File.join(dir, "sub")) { job.run(logger: SILENT) }]
      outcomes = results.map { [it.status, it.stats.read] }

      assert_equal [[:ok, 1], [:ok, 1]], outcomes
    end
  end

  def test_root_without_a_project_raises
    in_tmpdir do |dir|
      job = Metacrunch.job { params { param :input, String, default: root.join("x") } }
      error = Dir.chdir(dir) { assert_raises(Metacrunch::ProjectError) { job.run(logger: SILENT) } }

      assert_equal "no Metacrunchfile found in #{dir} or above", error.message
    end
  end

  def test_finding_the_root_does_not_load_the_project
    in_tmpdir do |dir|
      write_file(dir, "Metacrunchfile", "raise \"must not load\"\n")
      invoker = Metacrunch::Invoker.new(project: -> { raise "must not load" }, logger: SILENT, env: {})

      assert_equal Pathname(dir), Dir.chdir(dir) { invoker.root }
    end
  end

  def test_a_lazy_project_is_found_once_per_call
    in_tmpdir do |dir|
      write_file(dir, "Metacrunchfile", "")
      invoker = Metacrunch::Invoker.new(project: -> { raise "must not load" }, logger: SILENT, env: {})
      original = Metacrunch::Project.method(:find)
      lookups = 0
      counting = lambda do |path|
        lookups += 1
        original.call(path)
      end
      roots = override(Metacrunch::Project, :find, counting) { Dir.chdir(dir) { Array.new(3) { invoker.root } } }

      assert_equal [[Pathname(dir)] * 3, 1], [roots, lookups]
    end
  end

  def test_commands_get_root_in_params_too
    in_tmpdir do |dir|
      run = Metacrunch::Testing.invoke(write_project(dir), "where")

      assert_equal [File.join(dir, "out"), dir], run.value
    end
  end

  private

  def write_project(dir)
    write_root_project(dir)
    Metacrunch.load_project(dir)
  end

end
