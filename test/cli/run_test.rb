# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/jobs/lib/counting_source"

class RunTest < Minitest::Test

  include CliHelper
  include Override
  include ForkVariant::NoWorkerLeft

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  def test_runs_the_job
    code, stdout, stderr = cli("run", job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2")

    assert_equal [0, "3\n6\n"], [code, stdout]
    assert_match(/INFO  ok: read 3, written 2, rejected 1 \(Negative: 1\)/, stderr)
  end

  def test_workers_give_the_same_output
    code, stdout, stderr = cli("run", "-w", "2", job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2")

    assert_equal [0, "3\n6\n"], [code, stdout]
    assert_match(/INFO  ok: read 3, written 2, rejected 1 \(Negative: 1\)/, stderr)
  end

  def test_invalid_worker_counts_are_usage_errors
    zero = cli("run", "-w", "0", job("double.rb"), stdin: "1\n")
    word = cli("run", "--workers", "many", job("double.rb"), stdin: "1\n")

    assert_equal [2, 2], [zero.first, word.first]
    assert_match(/--workers must be a positive number or auto/, word.last)
  end

  def test_auto_workers_leave_a_core_for_the_parent
    seen = []
    choose = lambda do |workers|
      seen << workers
      Metacrunch::Executor::Inline.new
    end
    override(Metacrunch::Executor, :for, choose) { cli("run", "-w", "auto", job("double.rb"), stdin: "1\n") }

    assert_equal [Metacrunch::Executor.auto_workers], seen
  end

  def test_workers_need_fork
    code, _stdout, stderr = override(Metacrunch::Executor::Fork, :supported?, -> { false }) do
      cli("run", "-w", "2", job("double.rb"), stdin: "1\n")
    end

    assert_equal 2, code
    assert_match(/--workers needs Process.fork, which this platform lacks/, stderr)
  end

  def test_usage_errors_exit_with_the_usage_code
    assert_equal 2, cli("run").first
    assert_equal 2, cli("run", job("missing.rb")).first
    assert_equal 2, cli("run", job("numbers.rb"), "--factor", "x", "1").first
  end

  def test_usage_errors_are_explained_on_stderr
    _code, stdout, stderr = cli("run", job("numbers.rb"))

    assert_empty stdout
    assert_match(/Error: expected at least 1 argument\(s\) for numbers, got 0/, stderr)
    assert_match(/Usage: metacrunch run \[OPTIONS\] NAME\|FILE/, stderr)
  end

  def test_prints_job_help_without_running_the_job
    code, stdout, = cli("run", job("numbers.rb"), "--help")

    assert_equal 0, code
    assert_match(/Usage: metacrunch run \S*numbers\.rb \[JOB_PARAMS\.\.\.\] NUMBERS\.\.\./, stdout)
    assert_match(/--factor VALUE\s+Multiplier \(default: 1\)/, stdout)
  end

  def test_help_for_a_job_without_params
    code, stdout, = cli("run", "-j", "first", job("several.rb"), "--help")

    assert_equal [0, "Usage: metacrunch run #{job("several.rb")} [JOB_PARAMS...]\n\n"], [code, stdout]
  end

  def test_help_options_given_as_values_do_not_print_help
    code, stdout, stderr = cli("run", job("numbers.rb"), "--factor", "-h", "1")

    assert_equal [2, ""], [code, stdout]
    assert_match(/invalid value for --factor: "-h"/, stderr)
  end

  def test_an_aborted_run_reports_the_error_once
    _code, _stdout, stderr = cli("run", job("numbers.rb"), "0")

    assert_equal 1, stderr.scan("zero is not allowed").size
    assert_match(/INFO  aborted: read 1, written 0/, stderr)
  end

  def test_a_run_without_help_builds_the_job_once
    CountingSource.constructed = 0
    cli("run", job("counting.rb"))

    assert_equal 1, CountingSource.constructed
  end

  def test_logs_causes_of_errors_other_than_step_errors
    _code, _stdout, stderr = cli("run", job("chained_error.rb"))

    assert_match(/ERROR ArgumentError: source broke/, stderr)
    assert_match(/caused by IOError/, stderr)
  end

  def test_failed_records_exit_as_aborted_or_with_failures
    code, _stdout, stderr = cli("run", job("numbers.rb"), "0")

    assert_equal 1, code
    assert_match(/StepError: step map#2 failed at position 1: ZeroDivisionError: zero is not allowed/, stderr)
    assert_equal 3, cli("run", job("numbers.rb"), "--skip-errors", "0", "1").first
  end

  def test_selects_jobs_by_name
    assert_equal 0, cli("run", "-j", "second", job("several.rb")).first
    assert_equal 0, cli("run", "--job=first", job("several.rb")).first
    assert_match(/defines several jobs/, cli("run", job("several.rb"))[2])
  end

  def test_signals_exit_with_the_signal_code
    interrupt_code, _stdout, interrupt_log = cli("run", job("interrupted.rb"))
    term_code, _stdout, term_log = cli("run", job("terminated.rb"))

    assert_equal [130, 143], [interrupt_code, term_code]
    assert_match(/WARN  interrupted by SIGINT/, interrupt_log)
    assert_match(/WARN  interrupted by SIGTERM/, term_log)
  end

  def test_unexpected_errors_exit_as_aborted
    code, _stdout, stderr = cli("run", job("broken_recipe.rb"))

    assert_equal [1, 1], [code, cli("run", job("todo_recipe.rb")).first]
    assert_match(/NameError/, stderr)
  end

  def test_quiet_and_verbose_set_the_log_level
    _code, _stdout, quiet = cli("run", "-q", job("numbers.rb"), "1")
    _code, _stdout, verbose = cli("run", "-v", job("verbose.rb"))

    refute_match(/INFO/, quiet)
    assert_match(/DEBUG debug message/, verbose)
  end

  def test_a_job_without_source_and_sink_filters_stdin_to_stdout
    assert_equal [0, "2\n4\n"], cli("run", job("double.rb"), stdin: "1\n2\n").take(2)
  end

  def test_empty_stdin_gives_no_output
    assert_equal [0, ""], cli("run", job("double.rb"), stdin: "").take(2)
  end

  def test_a_job_without_source_does_not_wait_for_a_terminal
    code, _stdout, stderr = cli("run", job("double.rb"), stdin: TerminalInput.new)

    assert_equal 2, code
    assert_match(/job has no source and stdin is a terminal/, stderr)
  end

  def test_a_closed_stdout_ends_quietly_with_the_sigpipe_code
    stderr = StringIO.new
    command = Metacrunch::Cli.new(stdin: StringIO.new("1\n"), stdout: ClosedPipe.new, stderr:, env: {})

    assert_equal 141, command.run(["run", job("double.rb")])
    assert_empty stderr.string
  end

end
