# frozen_string_literal: true

require "test_helper"

class InvokerTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\", \"commands/*.rb\"\n",
    "jobs/numbers.rb" => <<~RUBY,
      Metacrunch.job "numbers" do
        params do
          param :skip, :bool, default: false
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        map { 100 / it }
        on_failure(params.skip ? :skip : :abort)
      end
    RUBY
    "jobs/term.rb" => <<~RUBY,
      Metacrunch.job "term" do
        params { param :output, String, required: true }

        source [1, 2]
        map { it == 2 ? raise(SignalException, "TERM") : it }
        sink Metacrunch::JsonLines::Writer.new(params.output), batch: 10
      end
    RUBY
    "transforms/scale.rb" => <<~RUBY,
      Metacrunch.transform "scale" do
        params { param :factor, Integer, default: 2 }

        map { it * params.factor }
      end
    RUBY
    "jobs/scaled.rb" => <<~RUBY,
      Metacrunch.job "scaled" do
        params do
          param :factor, Integer
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        use "scale", params: {factor: params.factor}
      end
    RUBY
    "commands/note.rb" => <<~RUBY,
      Metacrunch.command "note" do
        params { args :text, min: 1, max: 1 }

        run { params.text.first }
      end
    RUBY
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain" do
        params do
          param :tolerant, :bool, default: false
          args :numbers
        end

        run do
          invoke "numbers", params: {numbers: params.numbers}
        rescue Metacrunch::InvokeError
          raise unless params.tolerant

          :rescued
        end
      end
    RUBY
    "commands/outer.rb" => <<~RUBY,
      Metacrunch.command "outer" do
        params { args :numbers }

        run do
          [invoke("chain", params: {tolerant: true, numbers: params.numbers}),
           invoke("note", params: {text: "done"})]
        end
      end
    RUBY
    "commands/risky.rb" => <<~RUBY,
      Metacrunch.command "risky" do
        params { args :numbers }

        run do
          invoke "numbers", params: {skip: true, numbers: params.numbers}
          raise IOError, "disk full"
        end
      end
    RUBY
    "commands/careful.rb" => <<~RUBY,
      Metacrunch.command "careful" do
        params { args :numbers }

        run do
          invoke "risky", params: {numbers: params.numbers}
        rescue IOError
          :rescued
        end
      end
    RUBY
    "commands/boom.rb" => "Metacrunch.command(\"boom\") { run { raise IOError, \"disk full\" } }\n"
  }.freeze

  # A command from a gem: its file lives outside the project.
  GEM_COMMAND = <<~RUBY
    Metacrunch.command "secret:show" do
      params { secret :api_key, String, default: {credential: "catalog.api_key"} }

      run do
        invoke "secret"
        params.api_key.reverse
      end
    end
  RUBY

  NAMED_SECRET_JOB = <<~RUBY
    Metacrunch.job "secret" do
      params { secret :api_key, String, default: {credential: "catalog.api_key"} }

      source [params.api_key.reverse]
    end
  RUBY

  REVEAL = <<~RUBY
    Metacrunch.transform "reveal" do
      params { secret :api_key, String, default: {credential: "catalog.api_key"} }

      map { params.api_key.reverse }
    end
  RUBY

  def test_invoking_a_job_returns_its_result_and_writes_stdout
    with_project do |invoker, out|
      result = invoker.invoke("numbers", params: {numbers: ["4", Pathname("5")]})

      assert_equal [:ok, "25\n20\n"], [result.status, out.string]
    end
  end

  def test_an_aborted_job_raises_an_invoke_error_with_its_result
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("numbers", params: {numbers: ["0"]}) }

      assert_equal ["numbers", :aborted, Metacrunch::StepError], [error.name, error.result.status, error.cause.class]
      assert_match(/\Anumbers aborted: Metacrunch::StepError: step map#1 failed at position 1/, error.message)
    end
  end

  def test_failed_records_return_the_result_and_worsen_the_status
    with_project do |invoker|
      result = invoker.invoke("numbers", params: {skip: true, numbers: ["0", "4"]})

      assert_equal [:ok_with_failures, :ok_with_failures], [result.status, invoker.status]
    end
  end

  def test_a_command_returns_the_value_of_its_body
    with_project { |invoker| assert_equal "done", invoker.invoke("note", params: {text: "done"}).value }
  end

  def test_exceptions_from_a_body_propagate_unchanged
    with_project do |invoker|
      error = assert_raises(IOError) { invoker.invoke("boom") }

      assert_equal "disk full", error.message
    end
  end

  def test_invalid_arguments_for_the_target_raise_invoke_errors
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("note") }

      assert_equal "invoke note: expected at least 1 argument(s) for text, got 0", error.message
      assert_instance_of Metacrunch::ParamError, error.cause
    end
  end

  def test_unknown_names_raise_invoke_errors
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("nope") }

      assert_equal ["invoke nope: unknown job, transform, command or file: nope", "nope"], [error.message, error.name]
    end
  end

  def test_names_without_a_project_are_unknown
    error = assert_raises(Metacrunch::InvokeError) { invoker_for(nil).invoke("numbers") }

    assert_equal "invoke numbers: unknown job, transform, command or file: numbers (no Metacrunchfile found)",
                 error.message
  end

  def test_paths_run_without_a_project
    out = StringIO.new
    result = invoker_for(nil, stdin: StringIO.new("1\n2\n"), stdout: out).invoke(job("double.rb"))

    assert_equal [:ok, "2\n4\n"], [result.status, out.string]
  end

  def test_the_project_is_looked_up_once_when_a_name_is_first_needed
    with_project do |invoker|
      project = invoker.project
      calls = 0
      lookup = lambda do
        calls += 1
        project
      end
      lazy = invoker_for(lookup)
      2.times { lazy.invoke("note", params: {text: "x"}) }

      assert_equal 1, calls
    end
  end

  def test_a_name_wins_over_a_file_of_that_name_and_files_fill_in
    with_project do |invoker, out, root|
      write_file(root, "note", "# frozen_string_literal: true\n\nMetacrunch.job { source [\"file\"] }\n")
      write_file(root, "solo", "# frozen_string_literal: true\n\nMetacrunch.job { source [\"solo\"] }\n")
      value = Dir.chdir(root) { [invoker.invoke("note", params: {text: "name"}).value, invoker.invoke("solo").status] }

      assert_equal ["name", :ok], value
      assert_equal "\"solo\"\n", out.string
    end
  end

  def test_params_from_code_are_bound_by_name
    with_project do |invoker|
      result = invoker.invoke("numbers", params: {skip: true, numbers: ["0", Pathname("4")]})

      assert_equal [:ok_with_failures, 2], [result.status, result.stats.read]
    end
  end

  def test_nil_params_count_as_not_given
    with_project do |invoker, out|
      invoker.invoke("scaled", params: {factor: nil, numbers: ["1"]})

      assert_equal "2\n", out.string
    end
  end

  def test_unknown_params_raise_invoke_errors
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("numbers", params: {skp: true}) }

      assert_equal "invoke numbers: unknown parameter :skp (known: skip, numbers)", error.message
    end
  end

  def test_params_must_be_a_hash
    with_project do |invoker|
      error = assert_raises(ArgumentError) { invoker.invoke("note", params: ["x"]) }

      assert_equal "invoke note: params: must be a Hash, got [\"x\"]", error.message
    end
  end

  def test_arguments_as_on_the_command_line_are_gone
    with_project do |invoker|
      assert_raises(ArgumentError) { invoker.invoke("note", "done") }
    end
  end

  def test_workers_and_limit_apply_to_jobs_only
    with_project do |invoker|
      error = assert_raises(ArgumentError) { invoker.invoke("note", params: {text: "x"}, workers: 2) }

      assert_equal "note is a command; workers: and limit: apply to jobs and transforms", error.message
      assert_equal 2, invoker.invoke("numbers", params: {numbers: ["1", "2", "4"]}, limit: 2).stats.read
    end
  end

  def test_a_job_without_source_on_a_terminal_raises_an_invoke_error
    invoker = invoker_for(nil, stdin: TerminalInput.new)
    error = assert_raises(Metacrunch::InvokeError) { invoker.invoke(job("double.rb")) }

    # invoke has no -i, so the hint differs from the one of metacrunch run.
    assert_equal "invoke #{job("double.rb")}: #{job("double.rb")} reads JSON Lines from stdin, which is a terminal; " \
                 "pipe them into the command that invokes it", error.message
  end

  def test_invoking_a_command_returns_a_command_result
    with_project do |invoker|
      result = invoker.invoke("note", params: {text: "done"})

      assert_equal [Metacrunch::CommandResult, :ok, true, nil, "done"],
                   [result.class, result.status, result.ok?, result.error, result.value]
    end
  end

  def test_each_command_result_has_the_status_of_its_own_jobs
    with_project do |invoker|
      result = invoker.invoke("outer", params: {numbers: ["0"]})
      chain, note = result.value

      assert_equal [:ok_with_failures, :ok_with_failures, :ok], [result.status, chain.status, note.status]
      assert_equal [:rescued, "done"], [chain.value, note.value]
      assert_equal [:aborted, :ok_with_failures], [invoker.status, invoker.finished_status]
    end
  end

  def test_a_command_that_raises_keeps_the_status_of_its_jobs
    with_project do |invoker|
      result = invoker.invoke("careful", params: {numbers: ["0"]})

      assert_equal [:ok_with_failures, :rescued], [result.status, result.value]
    end
  end

  def test_logs_the_error_and_the_summary_with_the_name
    log = StringIO.new
    with_project(logger: Logger.new(log)) do |invoker|
      assert_raises(Metacrunch::InvokeError) { invoker.invoke("numbers", params: {numbers: ["0"]}) }

      assert_match(/numbers: Metacrunch::StepError: step map#1 failed/, log.string)
      assert_match(/numbers: aborted: read 1, written 0/, log.string)
    end
  end

  def test_a_signal_from_an_invoked_job_propagates_after_the_sink_was_flushed
    with_project do |invoker, _out, root|
      output = File.join(root, "term.jsonl")

      assert_raises(SignalException) { invoker.invoke("term", params: {output:}) }
      assert_equal "1\n", File.read(output)
    end
  end

  def test_the_environment_and_credentials_from_the_project_root_reach_a_gem_command
    in_tmpdir do |dir|
      root = File.join(dir, "project")
      glob = File.join(dir, "gem", "commands", "*.rb")
      write_ruby(dir, "gem/commands/secret.rb", GEM_COMMAND)
      write_ruby(root, "Metacrunchfile", "Metacrunch.load_files #{glob.inspect}, \"jobs/*.rb\"\n")
      write_ruby(root, "jobs/secret.rb", NAMED_SECRET_JOB)
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      out = StringIO.new
      invoker = invoker_for(Metacrunch.load_project(root), stdout: out, environment: "production")

      assert_equal SECRET.reverse, invoker.invoke("secret:show").value
      assert_equal "\"#{SECRET.reverse}\"\n", out.string
    end
  end

  def test_root_needs_a_project
    error = assert_raises(Metacrunch::ProjectError) { invoker_for(nil).root }

    assert_match(/\Ano Metacrunchfile found in .* or above\z/, error.message)
  end

  def test_project_invoke_runs_like_invoke_in_a_command
    with_project do |invoker|
      result = invoker.project.invoke("note", params: {text: "done"}, logger: Logger.new(nil), env: {})

      assert_equal "done", result.value
    end
  end

  def test_jobs_use_transforms_by_name
    with_project do |invoker, out|
      invoker.invoke("scaled", params: {numbers: ["1", "2"]})

      assert_equal "2\n4\n", out.string
    end
  end

  # A value given at use wins over the transform's default; nil (the job's
  # factor left unset) falls through to it.
  def test_values_at_use_win_over_the_default_and_nil_falls_through
    with_project do |invoker, out|
      invoker.invoke("scaled", params: {numbers: ["1"]})
      invoker.invoke("scaled", params: {factor: 5, numbers: ["1"]})

      assert_equal "2\n5\n", out.string
    end
  end

  def test_transforms_run_alone_like_jobs
    with_project(stdin: "1\n2\n") do |invoker, out|
      result = invoker.invoke("scale", params: {factor: 3})

      assert_equal [:ok, "3\n6\n"], [result.status, out.string]
    end
  end

  def test_the_credentials_of_the_job_reach_its_transforms
    in_tmpdir do |root|
      write_ruby(root, "Metacrunchfile", "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\"\n")
      write_ruby(root, "transforms/reveal.rb", REVEAL)
      write_ruby(root, "jobs/revealed.rb", "Metacrunch.job(\"revealed\") do\n  source [1]\n  use \"reveal\"\nend\n")
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      out = StringIO.new
      invoker_for(Metacrunch.load_project(root), stdout: out, environment: "production").invoke("revealed")

      assert_equal "\"#{SECRET.reverse}\"\n", out.string
    end
  end

  def test_a_path_for_use_loads_only_transforms
    with_project do |invoker|
      path = job("double.rb")
      error = assert_raises(Metacrunch::JobLoadError) { invoker.resolve(path, kind: Metacrunch::Transform) }

      assert_match(/no transform defined in .*double\.rb/, error.message)
    end
  end

  private

  # Yields an Invoker for a project with FILES, its stdout and the root.
  def with_project(logger: Logger.new(nil), env: {}, stdin: "")
    in_tmpdir do |root|
      FILES.each { |path, code| write_ruby(root, path, code) }
      out = StringIO.new
      invoker = invoker_for(Metacrunch.load_project(root), stdin: StringIO.new(stdin), stdout: out, logger:, env:)
      yield invoker, out, root
    end
  end

  def invoker_for(project, stdin: StringIO.new, stdout: StringIO.new, logger: Logger.new(nil), environment: nil,
                  env: {})
    Metacrunch::Invoker.new(project:, logger:, env:, stdin:, stdout:, environment:)
  end

  def write_ruby(root, path, code) = write_file(root, path, "# frozen_string_literal: true\n\n#{code}")

end
