# frozen_string_literal: true

require "test_helper"

class CheckTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  CATALOG = File.expand_path("../fixtures/catalog.json", __dir__)

  def test_describes_a_valid_job
    code, stdout, = cli("check", job("catalog.rb"), "--output", "/secret/dir", CATALOG)

    assert_equal 0, code
    assert_equal <<~TEXT, stdout
      #{job("catalog.rb")}: job "catalog" OK
        input      JsonArrayFile (id extractor)
        steps      reject#1 "Not public", filter#2, map#3, flat_map#4
        output     JsonLinesFile, batch 2
        rejects    JsonLinesFile
        failures   JsonLinesFile
        on_failure skip, max_failures 5
    TEXT
    refute_includes stdout, "secret"
  end

  def test_describes_a_filter_job
    assert_equal [0, <<~TEXT], cli("check", job("double.rb")).take(2)
      #{job("double.rb")}: job "double" OK
        input      stdin (JSON Lines)
        steps      map#1
        output     stdout (JSON Lines)
        on_failure abort
    TEXT
  end

  def test_opens_and_runs_nothing
    assert_equal 0, cli("check", job("unopenable.rb")).first
  end

  # A command's parameters are bound with its params file; its body does not
  # run.
  def test_checks_commands
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"commands/*.rb\"\n")
      write_file(root, "commands/touch.rb", <<~RUBY)
        Metacrunch.command("touch") do
          params { param :index, String, required: true }

          run { File.write("ran", "") }
        end
      RUBY
      write_file(root, "good.yml", "default: {index: x}\n")
      write_file(root, "typo.yml", "default: {indx: x}\n")
      good, typo = ["good.yml", "typo.yml"].map { |file| Dir.chdir(root) { cli("check", "--params", file, "touch") } }

      unknown = "typo.yml: default.indx: unknown parameter (known: index)"

      ran = File.exist?(File.join(root, "ran"))

      assert_equal [0, "touch: command \"touch\" OK\n", 2, true, false],
                   [*good.take(2), typo.first, typo.last.include?(unknown), ran], good.last
    end
  end

  def test_invalid_jobs_exit_with_the_usage_code
    code, _stdout, stderr = cli("check", job("broken_recipe.rb"))

    assert_equal [2, 2], [code, cli("check", job("numbers.rb")).first]
    assert_match(/Error: \S*broken_recipe\.rb: NameError: uninitialized constant UndefinedSource/, stderr)
  end

end
