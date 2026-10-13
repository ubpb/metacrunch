# frozen_string_literal: true

require "test_helper"

class ProjectTest < Minitest::Test

  include CredentialsHelper

  LOAD_ALL = "Metacrunch.load_files \"jobs/**/*.rb\", \"commands/**/*.rb\"\n"

  def test_finds_the_nearest_metacrunchfile_upward
    in_tmpdir do |root|
      outer = write_file(root, "Metacrunchfile", "")
      inner = write_file(root, "sub/Metacrunchfile", "")
      FileUtils.mkdir_p(File.join(root, "sub", "deep", "er"))

      assert_equal inner, Metacrunch::Project.find(File.join(root, "sub", "deep", "er"))
      assert_equal outer, Metacrunch::Project.find(root)
    end
  end

  def test_finds_nothing_without_metacrunchfile
    in_tmpdir { |root| assert_nil Metacrunch::Project.find(root) }
  end

  def test_loading_without_metacrunchfile_raises
    in_tmpdir do |root|
      error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_project(root) }

      assert_equal "no Metacrunchfile found in #{root} or above", error.message
    end
  end

  def test_loads_jobs_and_commands_from_relative_globs
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/a2c.rb" => job("a2c"),
                                   "jobs/sub/b.rb" => job("b"), "commands/release.rb" => command("catalog:release"))

      assert_equal ["a2c", "b", "catalog:release"], project.names
      assert_instance_of Metacrunch::Command, project.fetch("catalog:release")
      assert_equal [Pathname(root), File.join(root, "Metacrunchfile")], [project.root, project.file]
    end
  end

  def test_declarations_in_the_metacrunchfile_belong_to_the_project
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => command("inline"))

      assert_equal File.join(root, "Metacrunchfile"), project.fetch("inline").file
    end
  end

  def test_absolute_globs_load_files_outside_the_project
    in_tmpdir do |root|
      gem = write_file(root, "gem/commands/es.rb", ruby(command("es:create-index")))
      glob = File.join(root, "gem", "commands", "*.rb")
      project = load_project(File.join(root, "project"), "Metacrunchfile" => "Metacrunch.load_files #{glob.inspect}\n")

      assert_equal ["es:create-index"], project.names
      assert_equal gem, project.relative(project.fetch("es:create-index").file)
    end
  end

  def test_overlapping_globs_load_a_file_once
    in_tmpdir do |root|
      globs = "Metacrunch.load_files \"jobs/*.rb\", \"jobs/a*.rb\"\nMetacrunch.load_files \"jobs/a.rb\"\n"
      project = load_project(root, "Metacrunchfile" => globs, "jobs/a.rb" => job("a"))

      assert_equal "a", project.fetch("a").name
    end
  end

  def test_a_name_declared_twice_is_unusable_and_the_others_work
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/dup.rb" => job("dup"),
                                   "commands/dup.rb" => command("dup"), "jobs/ok.rb" => job("ok"))
      error = assert_raises(Metacrunch::ProjectError) { project.fetch("dup") }

      assert_equal "dup is declared more than once (commands/dup.rb, jobs/dup.rb); rename one", error.message
      assert_equal "ok", project.fetch("ok").name
    end
  end

  def test_a_file_that_fails_costs_only_its_names
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/broken.rb" => "Metacrunch.job \"x\" do\n",
                                   "jobs/ok.rb" => job("ok"))
      file, error = project.load_errors.first

      assert_equal [File.join(root, "jobs", "broken.rb"), SyntaxError], [file, error.class]
      assert_equal ["ok"], project.names
    end
  end

  def test_reserved_and_invalid_names_are_load_errors_of_their_file
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/run.rb" => job("run"),
                                   "jobs/upper.rb" => job("Upper"))
      messages = project.load_errors.map { |_file, error| error.message }

      assert_equal ["the name run is reserved for a built-in command",
                    "invalid job name \"Upper\": use a-z, 0-9, _ and -, in parts separated by :"], messages
      assert_empty project.names
    end
  end

  def test_an_error_in_the_metacrunchfile_is_a_project_error
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", ruby("raise \"broken\"\n"))
      error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_project(root) }

      assert_match(/could not load .*Metacrunchfile: RuntimeError: broken/, error.message)
    end
  end

  def test_a_reserved_name_in_the_metacrunchfile_is_a_project_error
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", ruby(command("help")))
      error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_project(root) }

      assert_equal "the name help is reserved for a built-in command", error.message
    end
  end

  def test_load_files_works_only_in_a_metacrunchfile
    error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_files("jobs/*.rb") }

    assert_equal "load_files works only in a Metacrunchfile", error.message
  end

  def test_files_that_the_metacrunchfile_loads_cannot_load_files
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL,
                                   "jobs/nested.rb" => "Metacrunch.load_files \"other/*.rb\"\n")

      assert_equal "load_files works only in a Metacrunchfile", project.load_errors.first.last.message
    end
  end

  def test_loading_a_project_twice_redefines_no_constants
    in_tmpdir do |root|
      write_project(root, "Metacrunchfile" => LOAD_ALL,
                          "jobs/a.rb" => "ProjectTest::LOADED_ONCE = true\n#{job("a")}")
      _stdout, stderr = capture_io { 2.times { Metacrunch.load_project(root) } }

      assert_empty stderr
    end
  end

  def test_relative_globs_work_below_a_root_with_glob_characters
    in_tmpdir do |dir|
      root = File.join(dir, "My Data [2026] {a,b}")
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/a.rb" => job("a"))

      assert_equal ["a"], project.names
    end
  end

  def test_unnamed_jobs_have_no_name_in_the_project
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/anon.rb" => "Metacrunch.job { source [] }\n")

      assert_empty project.names
      assert_empty project.load_errors
    end
  end

  def test_unknown_names_hint_at_files_that_did_not_load
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/broken.rb" => "Metacrunch.job(\n")
      error = assert_raises(Metacrunch::ProjectError) { project.fetch("nope") }

      assert_equal "unknown job or command: nope (1 file of the project did not load)", error.message
    end
  end

  def test_load_error_summaries_are_one_line_with_relative_paths
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/broken.rb" => "Metacrunch.job(\n")
      summary = project.load_error_summary(*project.load_errors.first)

      assert_match(%r{\Ajobs/broken\.rb: SyntaxError: jobs/broken\.rb:\d+: [^\n]+\z}, summary)
    end
  end

  private

  # Writes files below root, Ruby files with the magic comment, and loads
  # the project.
  def load_project(root, files)
    write_project(root, files)
    Metacrunch.load_project(root)
  end

  def write_project(root, files)
    files.each do |path, content|
      ruby_file = path.end_with?(".rb") || path == "Metacrunchfile"
      write_file(root, path, ruby_file ? ruby(content) : content)
    end
  end

  def ruby(code) = "# frozen_string_literal: true\n\n#{code}"

  def job(name) = "Metacrunch.job(#{name.inspect}) { source [] }\n"

  def command(name) = "Metacrunch.command(#{name.inspect}) { run { nil } }\n"

end
