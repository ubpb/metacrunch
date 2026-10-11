# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class NewTest < Minitest::Test

  include CliHelper

  LIB = File.expand_path("../../lib", __dir__)

  def test_creates_an_executable_filter_job_that_runs
    in_tmpdir do
      code, stdout, = cli("new", "jobs/mab2json")
      run_code, run_stdout, = cli("run", "jobs/mab2json.rb", stdin: "{\"id\":1}\n{\"x\":2}\n")

      assert_equal [0, "created jobs/mab2json.rb\n"], [code, stdout]
      assert File.executable?("jobs/mab2json.rb")
      assert_equal [0, "{\"id\":1}\n"], [run_code, run_stdout]
    end
  end

  def test_test_option_writes_a_passing_test
    in_tmpdir do |dir|
      cli("new", "--test", "jobs/pass.rb")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", LIB, "test/pass_test.rb", chdir: dir)

      assert_predicate status, :success?, stderr
    end
  end

  def test_refuses_to_overwrite_without_force
    in_tmpdir do
      cli("new", "job.rb")
      code, _stdout, stderr = cli("new", "job.rb")

      assert_equal 2, code
      assert_match(/job\.rb already exists; use --force to overwrite/, stderr)
      assert_equal 0, cli("new", "--force", "job.rb").first
    end
  end

  def test_class_names_of_tests_start_with_a_letter
    in_tmpdir do
      cli("new", "--test", "2go")

      assert_match(/^class Job2goTest < Minitest::Test$/, File.read("test/2go_test.rb"))
    end
  end

  def test_a_path_is_required
    assert_match(/Error: no path given/, cli("new")[2])
  end

  private

  def in_tmpdir(&)
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield dir } }
  end

end
