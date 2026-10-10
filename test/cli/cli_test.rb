# frozen_string_literal: true

require "test_helper"
require "metacrunch/cli"

class CliTest < Minitest::Test

  JOBS = File.expand_path("../fixtures/jobs", __dir__)

  def test_prints_the_version
    assert_equal [0, "#{Metacrunch::VERSION}\n", ""], cli("-v")
  end

  def test_prints_the_usage
    code, stdout, = cli("--help")

    assert_equal 0, code
    assert_match(/Usage: metacrunch \[-h\|-v\] JOB_FILE/, stdout)
  end

  def test_usage_errors_exit_with_the_usage_code
    assert_equal 2, cli.first
    assert_equal 2, cli(job("missing.rb")).first
    assert_equal 2, cli(job("numbers.rb"), "--factor", "x", "1").first
  end

  def test_usage_errors_are_explained_on_stderr
    _code, stdout, stderr = cli(job("numbers.rb"))

    assert_empty stdout
    assert_match(/Error: expected at least 1 argument\(s\) for numbers, got 0/, stderr)
  end

  def test_prints_job_help_without_running_the_job
    code, stdout, = cli(job("numbers.rb"), "--help")

    assert_equal 0, code
    assert_match(/--factor VALUE\s+Multiplier \(default: 1\)/, stdout)
    assert_match(/NUMBERS  Numbers to process  \(1 or more arguments\)/, stdout)
  end

  def test_help_for_a_job_without_params
    code, stdout, = cli(job("several.rb"), "--job", "first", "--help")

    assert_equal [0, "Usage: metacrunch #{job("several.rb")} [JOB_PARAMS...]\n\n"], [code, stdout]
  end

  def test_help_options_given_as_values_do_not_print_help
    code, stdout, stderr = cli(job("numbers.rb"), "--factor", "-h", "1")

    assert_equal [2, ""], [code, stdout]
    assert_match(/invalid value for --factor: "-h"/, stderr)
  end

  def test_an_aborted_run_reports_the_error_once
    _code, _stdout, stderr = cli(job("numbers.rb"), "0")

    assert_equal 1, stderr.scan("zero is not allowed").size
    assert_match(/INFO  aborted: read 1, written 0/, stderr)
  end

  def test_runs_the_job
    code, stdout, stderr = cli(job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2")

    assert_equal [0, "3\n6\n"], [code, stdout]
    assert_match(/INFO  ok: read 3, written 2, rejected 1 \(Negative: 1\)/, stderr)
  end

  def test_failed_records_exit_as_aborted_or_with_failures
    code, _stdout, stderr = cli(job("numbers.rb"), "0")

    assert_equal 1, code
    assert_match(/StepError: step map#2 failed at position 1: ZeroDivisionError: zero is not allowed/, stderr)
    assert_equal 3, cli(job("numbers.rb"), "--skip-errors", "0", "1").first
  end

  def test_selects_jobs_by_name
    assert_equal 0, cli(job("several.rb"), "--job", "second").first
    assert_equal 0, cli(job("several.rb"), "--job=first").first
    assert_match(/defines several jobs/, cli(job("several.rb"))[2])
  end

  def test_interrupt_exits_with_the_interrupted_code
    code, _stdout, stderr = cli(job("interrupted.rb"))

    assert_equal 130, code
    assert_match(/WARN  interrupted/, stderr)
  end

  def test_unexpected_errors_exit_as_aborted
    code, _stdout, stderr = cli(job("broken_recipe.rb"))

    assert_equal 1, code
    assert_match(/NameError/, stderr)
  end

  def test_script_errors_in_recipes_exit_as_aborted
    code, _stdout, stderr = cli(job("todo_recipe.rb"))

    assert_equal 1, code
    assert_match(/NotImplementedError/, stderr)
  end

  private

  def job(name)
    File.join(JOBS, name)
  end

  def cli(*args)
    code = nil
    stdout, stderr = capture_io { code = Metacrunch::Cli.new(env: {}).run(args) }
    [code, stdout, stderr]
  end

end
