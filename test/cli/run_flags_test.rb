# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RunFlagsTest < Minitest::Test

  include CliHelper

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_input_and_output_files_replace_source_and_sink
    input = File.join(@dir, "in.jsonl")
    output = File.join(@dir, "out.jsonl")
    File.write(input, "1\n2\n")
    code, stdout, = cli("run", "-i", input, "-o", output, job("numbers.rb"), "99")

    assert_equal [0, ""], [code, stdout]
    assert_equal "1\n2\n", File.read(output)
  end

  def test_rejects_and_errors_files_get_the_context
    bad = File.join(@dir, "bad.jsonl")
    code, = cli("run", "--on-error", "skip", "--rejects", bad, "--errors", bad, job("numbers.rb"),
                "--", "-1", "0", "2")
    lines = File.readlines(bad).map { JSON.parse(it) }

    assert_equal 3, code
    assert_equal([["Negative", -1], ["ZeroDivisionError", 0]],
                 lines.map { [it.dig("rejection", "reason") || it.dig("failure", "error"), it["record"]] })
  end

  def test_limit_stops_after_n_records
    assert_equal [0, "2\n4\n"], cli("run", "-n", "2", job("double.rb"), stdin: "1\n2\n3\n").take(2)
  end

  def test_invalid_option_values_are_usage_errors
    assert_match(/--limit must be at least 1/, cli("run", "--limit", "0", job("double.rb"))[2])
    assert_match(/--max-errors must not be negative/, cli("run", "--max-errors", "-1", job("double.rb"))[2])
    assert_match(/--on-error must be abort or skip/, cli("run", "--on-error", "maybe", job("double.rb"))[2])
  end

  def test_the_error_policy_can_be_overridden
    assert_equal 3, cli("run", "--on-error", "skip", job("numbers.rb"), "0", "1").first
    assert_match(/--max-errors needs the error policy skip/,
                 cli("run", "--max-errors", "3", job("numbers.rb"), "1")[2])
  end

  def test_invalid_json_lines_fail_like_records
    errors = File.join(@dir, "errors.jsonl")
    code, stdout, = cli("run", "--on-error", "skip", "--errors", errors, job("double.rb"), stdin: "1\n{oops\n3\n")
    failure = JSON.parse(File.read(errors))

    assert_equal [3, "2\n6\n"], [code, stdout]
    assert_equal ["{oops", 2, "source"], [failure["record"], failure["position"], failure.dig("failure", "step")]
  end

  def test_stats_are_written_as_json
    stats = File.join(@dir, "stats.json")
    cli("run", "--stats", stats, job("numbers.rb"), "0")
    data = JSON.parse(File.read(stats))

    assert_equal ["aborted", "Metacrunch::StepError", 1],
                 [data["status"], data.dig("error", "class"), data.dig("stats", "read")]
  end

  def test_stats_on_stdout
    code, stdout, = cli("run", "--stats", "-", "-o", File.join(@dir, "out.jsonl"), job("double.rb"), stdin: "1\n")

    assert_equal 0, code
    assert_equal({"status" => "ok", "error" => nil}, JSON.parse(stdout).slice("status", "error"))
  end

  def test_stdout_conflicts_are_usage_errors
    code, _stdout, stderr = cli("run", "--rejects", "-", job("double.rb"), stdin: "1\n")

    assert_equal 2, code
    assert_match(/stdout is used by both the default output \(the job has no sink\) and --rejects/, stderr)
  end

  def test_progress_is_shown_on_a_terminal
    stderr = TerminalOutput.new
    code, = cli("run", job("slow.rb"), stderr:)

    assert_equal 0, code
    assert_match(%r{read \d+ \(.*/s\)  written \d+}, stderr.string)
    assert_includes stderr.string, "\r\e[2K"
  end

  def test_no_progress_when_quiet_or_disabled
    quiet = TerminalOutput.new
    disabled = TerminalOutput.new
    cli("run", "-q", job("slow.rb"), stderr: quiet)
    cli("run", "--no-progress", job("slow.rb"), stderr: disabled)

    refute_includes quiet.string, "\e[2K"
    refute_includes disabled.string, "\e[2K"
  end

  def test_help_lists_the_run_options
    stdout = cli("run", "--help")[1]

    assert_match(/-i, --input PATH/, stdout)
    assert_match(/-n, --limit N/, stdout)
    assert_match(/--stats PATH/, stdout)
  end

end
