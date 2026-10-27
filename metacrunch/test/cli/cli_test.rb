# frozen_string_literal: true

require "test_helper"

class CliTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  USAGE_ERRORS = {
    [] => "no command, job, transform or file given",
    ["frobnicate"] => "unknown command frobnicate; run a job, transform or command with: metacrunch run frobnicate",
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
    assert_match(/^  run +Run a job, transform or command\n  check +Validate a job, transform or command/, stdout)
  end

  def test_the_usage_has_no_shorthand
    refute_match(/same as run/, cli("--help")[1])
  end

  def test_help_names_every_kind
    _code, stdout, = cli("--help")

    assert_match(/^  help +Show the help of a command, job, transform or file$/, stdout)
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

  def test_help_for_files
    code, stdout, = cli("help", job("numbers.rb"))
    missing = cli("help", "./missing.rb")

    assert_equal [0, cli("run", job("numbers.rb"), "--help")[1]], [code, stdout]
    assert_equal [2, "Error: unknown job, transform, command or file: ./missing.rb"],
                 [missing.first, missing.last.lines.first.chomp]
  end

  def test_help_for_an_unknown_name_in_a_project
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"jobs/*.rb\"\n")
      code, _stdout, stderr = Dir.chdir(root) { cli("help", "nope") }

      assert_equal [2, "Error: unknown job, transform, command or file: nope"], [code, stderr.lines.first.chomp]
    end
  end

  def test_help_for_a_name_in_a_broken_project
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "raise \"broken\"\n")
      code, _stdout, stderr = Dir.chdir(root) { cli("help", "catalog") }

      assert_equal 2, code
      assert_includes stderr, "broken"
    end
  end

  def test_a_job_file_needs_run
    code, _stdout, stderr = cli(job("numbers.rb"), "--factor", "3")

    assert_equal 2, code
    assert_includes stderr, "Error: unknown command #{job("numbers.rb")}; run a job, transform or command with: " \
                            "metacrunch run #{job("numbers.rb")}"
    assert_equal [0, "3\n6\n"], cli("run", job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2").take(2)
  end

end
