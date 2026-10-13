# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class LoaderTest < Minitest::Test

  FIXTURES = File.expand_path("../fixtures/jobs", __dir__)

  # file, name => expected message
  ERRORS = {
    "missing_file" => ["missing.rb", nil, /file not found: .*missing\.rb/],
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

  def test_loads_a_file_once_until_it_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "job.rb")
      FileUtils.cp(fixture("lazy.rb"), path)
      first = Metacrunch.load_job(path)
      second = Metacrunch.load_job(path)
      File.utime(Time.now, Time.now + 5, path)

      assert_same first, second
      refute_same first, Metacrunch.load_job(path)
    end
  end

  def test_collects_jobs_and_commands_with_their_file
    declarations = Metacrunch::Loader.cached(fixture("mixed.rb"))

    assert_equal [Metacrunch::Job, Metacrunch::Command], declarations.map(&:class)
    assert_equal [fixture("mixed.rb")] * 2, declarations.map(&:file)
  end

  def test_selects_a_command_by_name
    assert_equal "publish", Metacrunch::Loader.load(fixture("mixed.rb"), name: "publish").name
  end

  def test_load_job_considers_jobs_only
    assert_equal "export", Metacrunch.load_job(fixture("mixed.rb")).name
  end

  def test_a_file_with_only_commands_defines_no_job
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch.load_job(fixture("greet.rb")) }

    assert_match(/no job defined in .*greet\.rb/, error.message)
  end

  def test_several_jobs_and_commands_need_a_selection
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch::Loader.load(fixture("mixed.rb")) }

    assert_match(/defines several jobs and commands \(export, publish\); select one with --job NAME/, error.message)
  end

  def test_unknown_names_list_jobs_and_commands
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch::Loader.load(fixture("mixed.rb"), name: "x") }

    assert_match(/no job or command named x in .*available: export, publish/, error.message)
  end

  def test_kind_restricts_the_selection
    error = assert_raises(Metacrunch::JobLoadError) do
      Metacrunch::Loader.load(fixture("mixed.rb"), name: "export", kind: Metacrunch::Command)
    end

    assert_match(/no command named export in .*available: publish/, error.message)
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
