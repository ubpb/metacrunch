# frozen_string_literal: true

require "test_helper"

class ParamsFileCliTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "jobs/show.rb" => <<~RUBY,
      Metacrunch.job "show" do
        params { param :index, String, default: "d" }

        source [1]
        map { params.index }
      end
    RUBY
    "jobs/token.rb" => <<~RUBY,
      Metacrunch.job "token" do
        params { secret :token, String, required: true }

        source [1]
        map { params.token.reverse }
      end
    RUBY
    "commands/echo.rb" => <<~'RUBY',
      Metacrunch.command "echo" do
        params { param :index, String, default: "d" }

        run { logger.info("index: #{params.index}") }
      end
    RUBY
    "commands/relay.rb" => <<~RUBY,
      Metacrunch.command "relay" do
        params { param :index, String, default: "r" }

        run { invoke "show" }
      end
    RUBY
    "params.yml" => "default: {index: f}\nproduction: {index: p}\n",
    "typo.yml" => "default: {indx: f}\n",
    "secret.yml" => "production: {token: {credential: catalog.api_key}}\n"
  }.freeze

  def test_run_takes_values_from_the_file
    in_project do |root|
      outputs = [
        cli_in(root, "run", "--params", "params.yml", "show"),
        cli_in(root, "run", "-e", "production", "--params", "params.yml", "show"),
        cli_in(root, "run", "--params", "params.yml", "show", env: {"METACRUNCH_ENV" => "production"}),
        cli_in(root, "run", "-e", "production", "--params", "params.yml", "show", "--index", "c")
      ].map { it[1] }

      assert_equal ["\"f\"\n", "\"p\"\n", "\"p\"\n", "\"c\"\n"], outputs
    end
  end

  def test_check_and_trace_take_the_file
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "check", "--params", "typo.yml", "show")

      assert_equal [2, 0], [code, cli_in(root, "check", "--params", "params.yml", "show").first]
      assert_includes stderr, "Error: typo.yml: default.indx: unknown parameter (known: index)"
      assert_includes cli_in(root, "trace", "-n", "1", "--params", "params.yml", "show")[1], "\"f\""
    end
  end

  def test_a_command_by_name_takes_the_file
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "run", "-e", "production", "--params", "params.yml", "echo")

      assert_equal 0, code
      assert_includes stderr, "index: p"
    end
  end

  def test_invoked_jobs_do_not_see_the_file
    in_project do |root|
      assert_equal "\"d\"\n", cli_in(root, "run", "--params", "params.yml", "relay")[1]
    end
  end

  def test_help_works_with_a_broken_file
    in_project do |root|
      code, stdout, = cli_in(root, "run", "--params", "missing.yml", "show", "--help")

      assert_equal 0, code
      assert_includes stdout, "--index VALUE"
    end
  end

  def test_a_broken_file_is_a_usage_error
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "run", "--params", "missing.yml", "show")

      assert_equal 2, code
      assert_includes stderr, "Error: params file not found: missing.yml"
    end
  end

  def test_a_reference_reads_the_environments_credentials
    in_project do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      code, stdout, stderr = cli_in(root, "run", "-v", "-e", "production", "--params", "secret.yml", "token")

      assert_equal [0, "\"#{SECRET.reverse}\"\n"], [code, stdout], stderr
      refute_includes stderr, SECRET
    end
  end

  def test_verbose_logs_the_file_and_sections
    in_project do |root|
      stderr = cli_in(root, "run", "-v", "-e", "production", "--params", "params.yml", "show")[2]

      assert_includes stderr, "params: params.yml (production)"
    end
  end

  def test_help_lists_the_option
    assert_match(/--params FILE/, cli("run", "--help")[1])
    assert_match(/-e, --environment NAME +Environment of the credentials and the params file/,
                 cli("check", "--help")[1])
  end

  private

  def in_project
    in_tmpdir do |root|
      FILES.each do |path, code|
        write_file(root, path, path.end_with?(".yml") ? code : "# frozen_string_literal: true\n\n#{code}")
      end
      yield root
    end
  end

  # Runs the CLI in dir. cli passes env: {}, so ~/.metacrunch is never read.
  def cli_in(dir, *, **) = Dir.chdir(dir) { cli(*, **) }

end
