# frozen_string_literal: true

require "test_helper"
require "prism"
require "tmpdir"
require "metacrunch/generators"
require "metacrunch/testing"

class GeneratorsFilesTest < Minitest::Test

  Generators = Metacrunch::Generators
  ROOT = Pathname("/work/catalog")
  CWD = "/work/catalog"
  SOURCE = [{"id" => 1}, {"title" => "x"}].freeze

  def test_a_name_gets_a_file_and_a_test
    entries = plan("job", "catalog:ids").entries

    assert_equal([ROOT.join("jobs/catalog/ids.rb").to_s, ROOT.join("test/jobs/catalog/ids_test.rb").to_s],
                 entries.map(&:path))
  end

  # Executable job files are gone: metacrunch run names the file.
  def test_files_have_no_shebang_and_name_run
    contents = ["job", "transform", "command"].map { plan(it, "catalog:ids").entries.first.content }

    assert_empty contents.grep(/\A#!/)
    assert_equal 3, contents.grep(/#   metacrunch run catalog:ids/).size
  end

  def test_without_test_only_the_file
    assert_equal 1, plan("command", "tools/x", test: false).entries.size
  end

  def test_files_and_tests_are_ruby_without_warnings
    problems = ["job", "transform", "command"].product(["catalog:ids", "tools/fix"]).flat_map do |kind, argument|
      plan(kind, argument).entries.flat_map { |entry| ruby_problems(entry.content).map { "#{entry.path}: #{it}" } }
    end

    assert_empty problems
  end

  # RuboCop's line limit (120) holds for the generated files of long names.
  def test_long_names_keep_lines_within_120_characters
    name = "catalog:normalize:subject_headings_for_titles"
    long = ["job", "transform", "command"].flat_map do |kind|
      plan(kind, name).entries.flat_map { |entry| entry.content.lines.select { it.chomp.length > 120 } }
    end

    assert_empty long
  end

  def test_the_comment_shows_how_to_run_it
    by_name = plan("job", "catalog:ids").entries.first.content
    by_path = plan("job", "tools/fix").entries.first.content

    assert_includes by_name, "#   metacrunch run catalog:ids < in.jsonl > out.jsonl\n"
    assert_includes by_path, "#   metacrunch run tools/fix.rb < in.jsonl > out.jsonl\n"
  end

  def test_a_transform_shows_how_jobs_use_it
    assert_includes plan("transform", "tools/tidy").entries.first.content, %(#   use "tools/tidy.rb"\n)
  end

  def test_tests_by_name_use_the_helper_and_tests_by_path_the_file
    by_name = plan("job", "catalog:ids").entries.last.content
    by_path = plan("job", "tools/fix").entries.last.content

    assert_includes by_name, %(require_relative "../../test_helper"\n)
    assert_includes by_path, %(FILE = File.expand_path("../tools/fix.rb", __dir__)\n)
  end

  def test_no_desc_without_the_option
    assert_includes plan("job", "catalog:ids").entries.first.content, %(Metacrunch.job "catalog:ids" do\n)
  end

  def test_a_job_keeps_records_with_an_id_and_marks_missing_titles
    in_project do |root|
      write(plan("job", "catalog:ids", root:), root)
      result = Metacrunch::Testing.run(Metacrunch.load_job(root.join("jobs/catalog/ids.rb").to_s), source: SOURCE)

      assert_equal [[{"id" => 1}], {"No id" => 1}, {"No title" => 1}],
                   [result.records, result.stats.rejected, result.stats.marked]
    end
  end

  def test_a_transform_runs_alone_with_a_source
    in_project do |root|
      write(plan("transform", "catalog:clean", root:), root)
      transform = Metacrunch.load_transform(root.join("transforms/catalog/clean.rb").to_s)
      result = Metacrunch::Testing.run(transform, source: [{"id" => 1}, {"title" => "x"}, {"id" => 2, "title" => "y"}])

      assert_equal [[{"id" => 1}, {"id" => 2, "title" => "y"}], {"No title" => 1}],
                   [result.records, result.stats.marked]
    end
  end

  def test_a_command_runs_without_invoking
    in_project do |root|
      write(plan("command", "catalog:release", root:), root)
      run = Metacrunch::Testing.invoke(Metacrunch.load_command(root.join("commands/catalog/release.rb").to_s))

      assert_equal [:ok, []], [run.status, run.invoked]
    end
  end

  def test_desc_becomes_a_ruby_string
    desc = %(Say "hi" \#{x} – ü)
    in_project do |root|
      write(plan("transform", "clean", root:, desc:), root)

      assert_equal desc, Metacrunch.load_transform(root.join("transforms/clean.rb").to_s).desc
    end
  end

  private

  def plan(kind, argument, root: ROOT, desc: nil, test: true)
    root = nil if Metacrunch::Names.path?(argument)
    Generators::Files.plan(Generators::Target.for(kind, argument, cwd: CWD, root:), desc:, test:)
  end

  def write(plan, root)
    plan.write(force: false, out: StringIO.new, cwd: root.to_s)
  end

  # Parse errors and warnings, verbose ones included.
  def ruby_problems(code)
    result = Prism.parse(code)
    (result.errors + result.warnings).map { "#{it.location.start_line}: #{it.message}" }
  end

  def in_project
    Dir.mktmpdir { |dir| yield Pathname(File.realpath(dir)) }
  end

end
