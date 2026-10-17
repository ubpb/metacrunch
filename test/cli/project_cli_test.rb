# frozen_string_literal: true

require "test_helper"

class ProjectCliTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "jobs/numbers.rb" => <<~RUBY,
      Metacrunch.job "numbers", desc: "Divide 100 by each number" do
        params do
          param :skip, :bool, default: false, desc: "Skip failed records"
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        map { 100 / it }
        on_error(params.skip ? :skip : :abort)
      end
    RUBY
    "jobs/interrupted.rb" => <<~RUBY,
      Metacrunch.job "interrupted" do
        source [1]
        map { raise Interrupt }
      end
    RUBY
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain", desc: "numbers, then a note" do
        params do
          param :skip, :bool, default: false
          param :tolerant, :bool, default: false
          args :numbers
        end

        run do
          begin
            invoke "numbers", *(params.skip ? ["--skip"] : []), *params.numbers
          rescue Metacrunch::InvokeError
            raise unless params.tolerant
          end
          invoke "note", "done"
        end
      end
    RUBY
    "commands/note.rb" => <<~'RUBY',
      Metacrunch.command "note", desc: "Log a note" do
        params { args :text, min: 1, max: 1 }

        run { logger.info("note: #{params.text.first}") }
      end
    RUBY
    "commands/stop.rb" => <<~RUBY,
      Metacrunch.command "stop" do
        run do
          invoke "interrupted"
          invoke "note", "after"
        end
      end
    RUBY
    "commands/fail.rb" => "Metacrunch.command(\"fail\") { run { raise IOError, \"disk full\" } }\n"
  }.freeze

  # A command outside jobs/ and commands/, run by path.
  TOOL = "Metacrunch.command(\"tools:release\") { run { invoke \"note\", \"from tools\" } }\n"
  # Writes a file if its body ever runs.
  DANGER = "Metacrunch.command(\"danger\") { run { File.write(\"ran\", \"\") } }\n"
  DUPLICATE = "Metacrunch.job(\"note\") { source [] }\n"
  BROKEN = "Metacrunch.job(\n"

  def test_runs_a_job_by_name_from_a_subdirectory
    in_project do |root|
      code, stdout, stderr = cli_in(File.join(root, "jobs"), "numbers", "4", "5")

      assert_equal [0, "25\n20\n"], [code, stdout]
      assert_match(/INFO  ok: read 2, written 2/, stderr)
    end
  end

  def test_runs_a_command_by_name_also_with_run
    in_project do |root|
      short = cli_in(root, "note", "hello")
      long = cli_in(root, "run", "note", "hi")

      assert_equal [0, 0], [short.first, long.first]
      assert_match(/INFO  note: hello/, short.last)
    end
  end

  def test_a_chain_exits_with_the_worst_status
    in_project do |root|
      results = [["4"], ["0"], ["--skip", "0", "4"], ["--tolerant", "0"]].map { cli_in(root, "chain", *it) }
      aborted = results[1].last

      assert_equal [0, 1, 3, 3], results.map(&:first)
      assert_match(/ERROR numbers aborted: Metacrunch::StepError/, aborted)
      refute_match(/note: done/, aborted)
    end
  end

  def test_an_exception_in_the_body_exits_with_1_and_its_backtrace
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "fail")

      assert_equal 1, code
      assert_match(/disk full \(IOError\)/, stderr)
    end
  end

  def test_invalid_params_of_a_command_are_a_usage_error
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "note")

      assert_equal 2, code
      assert_match(/Error: expected at least 1 argument\(s\) for text, got 0/, stderr)
    end
  end

  def test_ctrl_c_in_an_invoked_job_ends_the_chain_by_the_signal
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "stop")

      assert_equal 130, code
      refute_match(/note: after/, stderr)
    end
  end

  def test_invoked_jobs_show_progress_as_run_does
    slowly = "Metacrunch.command(\"slowly\") { run { invoke #{job("slow.rb").inspect} } }\n"
    in_project("commands/slowly.rb" => slowly) do |root|
      shown = TerminalOutput.new
      hidden = TerminalOutput.new
      cli_in(root, "slowly", stderr: shown)
      cli_in(root, "run", "--no-progress", "slowly", stderr: hidden)

      assert_includes shown.string, "\r\e[2K"
      refute_includes hidden.string, "\e[2K"
    end
  end

  def test_help_for_names_shows_the_description
    in_project do |root|
      code, stdout, = cli_in(root, "numbers", "--help")
      usage = /\AUsage: metacrunch run numbers \[JOB_PARAMS\.\.\.\] NUMBERS\.\.\.\n\nDivide 100 by each number\n\n/

      assert_equal 0, code
      assert_match(usage, stdout)
      assert_equal cli_in(root, "note", "--help"), cli_in(root, "help", "note")
    end
  end

  def test_help_never_runs_a_body
    in_project("commands/danger.rb" => DANGER) do |root|
      code, stdout, = cli_in(root, "danger", "--help")

      assert_equal [0, "Usage: metacrunch run danger [PARAMS...]\n\n"], [code, stdout]
      refute_path_exists File.join(root, "ran")
    end
  end

  def test_the_usage_lists_jobs_and_commands_with_their_descriptions
    in_project do |root|
      code, stdout, = cli_in(root, "--help")

      assert_equal 0, code
      assert_match(/^Jobs \(#{Regexp.escape(root)}\):\n  interrupted\n  numbers +Divide 100 by each number\n/, stdout)
      assert_match(/^Project commands \(.*\):\n  chain +numbers, then a note\n  fail\n  note +Log a note\n  stop\n/,
                   stdout)
    end
  end

  def test_the_usage_lists_duplicates_and_files_that_did_not_load_without_warnings
    in_project("jobs/dup.rb" => DUPLICATE, "jobs/broken.rb" => BROKEN) do |root|
      _code, stdout, stderr = cli_in(root, "--help")

      assert_match(/^  note +\(declared more than once, unusable\)$/, stdout)
      assert_match(%r{^Not loaded:\n  jobs/broken\.rb: SyntaxError: jobs/broken\.rb:\d+: }, stdout)
      assert_empty stderr
    end
  end

  def test_a_failing_metacrunchfile_shows_in_the_usage_and_stops_names
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nraise \"broken\"\n")
      help = cli_in(root, "--help")
      named = cli_in(root, "numbers")

      assert_equal [0, 2], [help.first, named.first]
      assert_match(/^Project:\n  could not load .*Metacrunchfile: RuntimeError: broken$/, help[1])
      assert_match(/Error: could not load .*Metacrunchfile: RuntimeError: broken/, named.last)
    end
  end

  def test_files_that_did_not_load_give_one_warning_each
    in_project("jobs/broken.rb" => BROKEN) do |root|
      quiet = cli_in(root, "note", "x")
      verbose = cli_in(root, "run", "-v", "note", "x")

      assert_equal [0, 1], [quiet.first, quiet.last.scan("WARN  jobs/broken.rb: SyntaxError").size]
      assert_match(%r{WARN  jobs/broken\.rb: SyntaxError: .* \(-v after run, check or trace shows details\)},
                   quiet.last)
      assert_match(/DEBUG .*broken\.rb:\d+: syntax error/m, verbose.last)
    end
  end

  def test_unknown_names_hint_at_files_that_did_not_load
    in_project("jobs/broken.rb" => BROKEN) do |root|
      code, _stdout, stderr = cli_in(root, "nope")

      assert_equal 2, code
      assert_match(/Error: unknown job, transform, command or file: nope \(1 file of the project did not load\)/,
                   stderr)
    end
  end

  def test_unknown_names_outside_a_project
    in_tmpdir do |dir|
      code, _stdout, stderr = cli_in(dir, "nope")

      assert_equal 2, code
      assert_match(/Error: unknown job, transform, command or file: nope \(no Metacrunchfile found\)/, stderr)
    end
  end

  def test_a_duplicate_name_is_a_usage_error_naming_both_files
    in_project("jobs/dup.rb" => DUPLICATE) do |root|
      code, _stdout, stderr = cli_in(root, "note", "x")

      assert_equal 2, code
      assert_match(%r{Error: note is declared more than once \(commands/note\.rb, jobs/dup\.rb\); rename one}, stderr)
    end
  end

  def test_job_options_are_a_usage_error_for_commands
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "run", "-w", "2", "note", "x")

      assert_equal 2, code
      assert_match(/Error: note is a command; -w applies to jobs/, stderr)
    end
  end

  def test_check_and_trace_take_jobs_only
    in_project do |root|
      results = ["check", "trace"].map { cli_in(root, it, "note", "x") }

      assert_equal [2, 2], results.map(&:first)
      assert_match(/Error: note is a command; check takes jobs/, results.first.last)
    end
  end

  def test_check_takes_job_names
    in_project do |root|
      code, stdout, = cli_in(root, "check", "numbers", "4")

      assert_equal [0, "numbers: job \"numbers\" OK"], [code, stdout.lines.first.chomp]
    end
  end

  def test_job_selection_applies_to_files_only
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "run", "-j", "x", "numbers")

      assert_equal 2, code
      assert_match(/Error: --job selects in a file; numbers is a name/, stderr)
    end
  end

  def test_builtins_and_paths_never_load_the_metacrunchfile
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nraise \"must not be loaded\"\n")
      results = [
        cli_in(root, "run", job("double.rb"), stdin: "1\n"), cli_in(root, job("double.rb"), stdin: "1\n"),
        cli_in(root, "check", job("double.rb")), cli_in(root, "--version"), cli_in(root, "help", "run")
      ]

      assert_equal [0] * 5, results.map(&:first)
      assert(results.none? { it.last.include?("must not be loaded") })
    end
  end

  def test_commands_run_by_path
    in_project("tools/release.rb" => TOOL) do |root|
      code, _stdout, stderr = cli_in(File.join(root, "jobs"), "run", File.join(root, "tools", "release.rb"))
      greeting = cli_in(root, job("greet.rb"), "--name", "Ada")

      assert_equal [0, 0], [code, greeting.first]
      assert_match(/INFO  note: from tools/, stderr)
      assert_match(/INFO  hello, Ada/, greeting.last)
    end
  end

  def test_a_name_wins_over_a_file_of_that_name
    in_project("note" => "Metacrunch.job { source [1] }\n") do |root|
      code, stdout, stderr = cli_in(root, "note", "x")

      assert_equal [0, ""], [code, stdout]
      assert_match(/INFO  note: x/, stderr)
    end
  end

  private

  # Yields the root of a temporary project with FILES and extra; every file
  # gets the magic comment.
  def in_project(extra = {})
    in_tmpdir do |root|
      FILES.merge(extra).each { |path, code| write_file(root, path, "# frozen_string_literal: true\n\n#{code}") }
      yield root
    end
  end

  # Runs the CLI in dir. cli passes env: {}, so ~/.metacrunch is never read.
  def cli_in(dir, *, **) = Dir.chdir(dir) { cli(*, **) }

end
