# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class NewTest < Minitest::Test

  include CliHelper

  SKELETON = ["Metacrunchfile", "Gemfile", "Rakefile", "jobs/.keep", "transforms/.keep", "commands/.keep",
              "lib/.keep", "test/test_helper.rb", "test/project_test.rb"].freeze
  USAGE_ERRORS = {
    [] => "no directory given",
    ["a", "b"] => "unexpected arguments: b",
    ["jobs/x.rb"] => "new creates a project; for a job file use metacrunch generate job jobs/x.rb"
  }.freeze

  def test_creates_a_project_that_loads
    in_tmpdir do |dir|
      code, stdout, stderr = cli("new", "catalog")
      project = Metacrunch.load_project(File.join(dir, "catalog"))

      assert_equal [0, ""], [code, stderr]
      assert_equal SKELETON.map { "created catalog/#{it}" }, stdout.lines(chomp: true).first(SKELETON.size)
      assert_equal [[], []], [project.names, project.load_errors]
    end
  end

  def test_prints_the_next_steps
    in_tmpdir do
      _code, stdout, = cli("new", "my catalog")

      assert_equal ["Next steps:", "  cd my\\ catalog", "  bundle install", "  bundle exec metacrunch generate job NAME",
                    "  bundle exec rake"], stdout.lines(chomp: true).last(5)
    end
  end

  def test_the_working_directory_needs_no_cd
    in_tmpdir do
      _code, stdout, = cli("new", ".")

      assert_path_exists "Metacrunchfile"
      refute_match(/^  cd /, stdout)
    end
  end

  def test_keeps_other_files_of_the_directory
    in_tmpdir do
      FileUtils.mkdir_p("catalog/jobs")
      File.write("catalog/jobs/old.rb", "x")
      code, = cli("new", "catalog")

      assert_equal [0, "x"], [code, File.read("catalog/jobs/old.rb")]
    end
  end

  def test_refuses_existing_files_of_the_skeleton_without_force
    in_tmpdir do
      FileUtils.mkdir_p("catalog")
      ["Gemfile", "Rakefile"].each { File.write("catalog/#{it}", "mine") }
      code, _stdout, stderr = cli("new", "catalog")

      assert_equal [2, "Error: catalog/Gemfile, catalog/Rakefile already exist; use --force to overwrite"],
                   [code, stderr.lines.first.chomp]
      refute_path_exists "catalog/Metacrunchfile"
    end
  end

  def test_force_overwrites_the_skeleton_only
    in_tmpdir do
      FileUtils.mkdir_p("catalog")
      ["Gemfile", "notes.txt"].each { File.write("catalog/#{it}", "mine") }
      code, = cli("new", "catalog", "--force")

      assert_equal 0, code
      assert_equal ["mine", true], [File.read("catalog/notes.txt"), File.read("catalog/Gemfile").include?("metacrunch")]
    end
  end

  def test_notes_a_project_inside_another
    in_tmpdir do |dir|
      File.write("Metacrunchfile", "")
      code, _stdout, stderr = cli("new", "sub")

      assert_equal [0, "note: inside the project #{dir}; below sub/ names resolve in the new project\n"],
                   [code, stderr]
    end
  end

  def test_a_file_is_no_directory
    in_tmpdir do
      File.write("catalog", "")

      assert_equal "Error: catalog is a file", cli("new", "catalog")[2].lines.first.chomp
    end
  end

  USAGE_ERRORS.each_with_index do |(args, message), index|
    define_method("test_usage_error_#{index}") do
      in_tmpdir do
        code, _stdout, stderr = cli("new", *args)

        assert_equal [2, "Error: #{message}"], [code, stderr.lines.first.chomp]
        assert_empty Dir.children(".")
      end
    end
  end

  def test_help_shows_the_usage
    assert_match(/\AUsage: metacrunch new \[--force\] DIR\n\nCreate a project\./, cli("help", "new")[1])
  end

  private

  def in_tmpdir
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield File.realpath(dir) } }
  end

end
