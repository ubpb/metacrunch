# frozen_string_literal: true

require "test_helper"

class CheckTest < Minitest::Test

  include CliHelper

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

  def test_invalid_jobs_exit_with_the_usage_code
    code, _stdout, stderr = cli("check", job("broken_recipe.rb"))

    assert_equal [2, 2], [code, cli("check", job("numbers.rb")).first]
    assert_match(/Error: \S*broken_recipe\.rb: NameError: uninitialized constant UndefinedSource/, stderr)
  end

end
