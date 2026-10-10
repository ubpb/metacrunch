# frozen_string_literal: true

require "test_helper"

class LoaderTest < Minitest::Test

  FIXTURES = File.expand_path("../fixtures/jobs", __dir__)

  # file, name => expected message
  ERRORS = {
    "missing_file" => ["missing.rb", nil, /job file not found/],
    "no_job" => ["none.rb", nil, /no job defined/],
    "several_jobs_without_name" => ["several.rb", nil, /defines several jobs \(first, second\)/],
    "unknown_name" => ["several.rb", "third", /no job named third .*available: first, second/],
    "syntax_error" => ["broken.rb", nil, /could not load .*broken\.rb: SyntaxError/]
  }.freeze

  def test_loads_the_only_job_without_evaluating_it
    assert_equal "lazy", Metacrunch.load_job(fixture("lazy.rb")).name
  end

  def test_selects_a_job_by_name
    assert_equal "second", Metacrunch.load_job(fixture("several.rb"), name: "second").name
  end

  def test_jobs_defined_outside_a_file_are_not_collected
    Metacrunch.job("inline") { source [] }

    assert_equal "lazy", Metacrunch.load_job(fixture("lazy.rb")).name
  end

  ERRORS.each do |description, (file, name, message)|
    define_method("test_load_error_#{description}") do
      error = assert_raises(Metacrunch::JobLoadError) { Metacrunch.load_job(fixture(file), name:) }

      assert_match message, error.message
    end
  end

  private

  def fixture(file)
    File.join(FIXTURES, file)
  end

end
