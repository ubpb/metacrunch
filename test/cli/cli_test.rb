# frozen_string_literal: true

require "test_helper"

class CliTest < Minitest::Test

  include CliHelper

  USAGE_ERRORS = {
    [] => "no command, job or file given",
    ["frobnicate"] => "unknown job, transform, command or file: frobnicate (no Metacrunchfile found)",
    ["-v"] => "unknown option -v",
    ["help", "frobnicate"] => "unknown job, transform, command or file: frobnicate (no Metacrunchfile found)"
  }.freeze

  def test_prints_the_version
    assert_equal [0, "#{Metacrunch::VERSION}\n", ""], cli("--version")
  end

  def test_prints_the_usage
    code, stdout, = cli("--help")

    assert_equal 0, code
    assert_match(/Usage: metacrunch COMMAND \[OPTIONS\] NAME\|FILE/, stdout)
    assert_match(/^  run +Run a job, transform or command$/, stdout)
  end

  def test_help_without_a_command_prints_the_usage
    assert_equal cli("--help"), cli("help")
  end

  def test_help_about_help_prints_the_usage
    assert_equal cli("--help"), cli("help", "help")
  end

  def test_help_for_a_command
    code, stdout, = cli("help", "run")

    assert_equal [0, cli("run", "--help")[1]], [code, stdout]
    assert_match(/Usage: metacrunch run \[OPTIONS\] NAME\|FILE/, stdout)
    assert_match(/-j, --job NAME/, stdout)
  end

  def test_usage_errors_exit_with_the_usage_code
    results = USAGE_ERRORS.keys.map { |args| cli(*args) }

    assert_equal [2] * USAGE_ERRORS.size, results.map(&:first)
    assert_equal(USAGE_ERRORS.values, results.map { |_code, _stdout, stderr| stderr[/Error: (.*)$/, 1] })
  end

  def test_a_job_file_as_first_argument_is_run
    assert_equal [0, "3\n6\n"], cli(job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2").take(2)
  end

end
