# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class GenerateTest < Minitest::Test

  include CliHelper
  include Override

  METACRUNCHFILE = %(Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"\n)
  USAGE_ERRORS = {
    [] => "no kind given (job, transform, command, source or sink)",
    ["model", "x"] => "unknown kind model (job, transform, command, source or sink)",
    ["job"] => "no name or path given",
    ["job", "a", "b"] => "unexpected arguments: b",
    ["job", "Catalog"] => '"Catalog" is not a valid job name; use a-z, 0-9, _ and -, in parts separated by :',
    ["job", "help"] => '"help" is the name of a built-in command; choose another name',
    ["source", "lines", "--desc", "x"] => "--desc is for jobs, transforms and commands",
    ["job", "x", "--desc", "a\nb"] => "desc must be one line of text",
    ["sink", "file"] => '"file" would reopen File; choose another name'
  }.freeze

  def test_a_name_goes_below_the_project_root
    in_project do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      code, stdout, stderr = Dir.chdir(File.join(root, "lib")) { cli("generate", "job", "catalog:ids") }

      assert_equal [0, "created ../jobs/catalog/ids.rb\ncreated ../test/jobs/catalog/ids_test.rb\n", ""],
                   [code, stdout, stderr]
      assert File.executable?(File.join(root, "jobs/catalog/ids.rb"))
    end
  end

  def test_every_kind_by_name_has_its_place
    in_project do |root|
      ["transform catalog:clean", "command es:create-index", "source marc:dump", "sink files:json"].each do |args|
        cli("generate", *args.split)
      end

      assert_equal ["commands/es/create_index.rb", "lib/files/json.rb", "lib/marc/dump.rb",
                    "test/commands/es/create_index_test.rb", "test/lib/files/json_test.rb",
                    "test/lib/marc/dump_test.rb", "test/transforms/catalog/clean_test.rb",
                    "transforms/catalog/clean.rb"],
                   Dir.glob("**/*.rb", base: root).sort
    end
  end

  def test_a_path_works_without_project_and_without_test
    in_tmpdir do
      code, stdout, = cli("generate", "command", "tools/release")

      assert_equal [0, "created tools/release.rb\n"], [code, stdout]
      refute_path_exists "test"
    end
  end

  def test_test_option_adds_a_test_for_a_path
    in_tmpdir do
      assert_equal "created tools/fix.rb\ncreated test/fix_test.rb\n",
                   cli("generate", "job", "--test", "tools/fix.rb")[1]
    end
  end

  def test_no_test_option_leaves_out_the_test_of_a_name
    in_project do |root|
      cli("generate", "transform", "clean", "--no-test")

      refute_path_exists File.join(root, "test/transforms/clean_test.rb")
    end
  end

  def test_desc_goes_into_the_declaration
    in_project do |root|
      cli("generate", "job", "--desc", "Extract the ids", "catalog:ids")

      assert_includes File.read(File.join(root, "jobs/catalog/ids.rb")),
                      %(Metacrunch.job "catalog:ids", desc: "Extract the ids" do\n)
    end
  end

  def test_sources_and_sinks_tell_how_to_use_them
    in_project do
      assert_equal "In a job: require_relative the file, then sink Files::Json.new(...)",
                   cli("generate", "sink", "files:json")[1].lines.last.chomp
    end
  end

  def test_a_name_needs_a_project
    in_tmpdir do |dir|
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: no Metacrunchfile found in #{dir} or above; give a path (./ids.rb) or create a " \
                       "project with metacrunch new"], [code, stderr.lines.first.chomp]
    end
  end

  def test_a_name_needs_a_metacrunchfile_that_loads
    in_project("Metacrunchfile" => "raise \"broken\"\n") do |root|
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: could not load #{root}/Metacrunchfile: RuntimeError: broken"],
                   [code, stderr.lines.first.chomp]
    end
  end

  def test_refuses_a_name_declared_in_another_file
    in_project("commands/x.rb" => %(Metacrunch.command("catalog:ids") { run { nil } }\n)) do |root|
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: catalog:ids is already declared in commands/x.rb"], [code, stderr.lines.first.chomp]
      refute_path_exists File.join(root, "jobs/catalog/ids.rb")
    end
  end

  def test_force_regenerates_the_file_that_declares_the_name
    in_project do
      cli("generate", "job", "catalog:ids")
      code, stdout, stderr = cli("generate", "job", "catalog:ids", "--force")

      assert_equal [0, ""], [code, stderr]
      assert_includes stdout, "created jobs/catalog/ids.rb\n"
    end
  end

  def test_refuses_to_overwrite_without_force
    in_project do |root|
      FileUtils.mkdir_p(File.join(root, "test/jobs/catalog"))
      File.write(File.join(root, "test/jobs/catalog/ids_test.rb"), "mine")
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: test/jobs/catalog/ids_test.rb already exists; use --force to overwrite"],
                   [code, stderr.lines.first.chomp]
      refute_path_exists File.join(root, "jobs/catalog/ids.rb")
    end
  end

  def test_notes_a_name_the_metacrunchfile_does_not_load
    in_project("Metacrunchfile" => %(Metacrunch.load_files "jobs/*.rb"\n)) do
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [0, "note: jobs/catalog/ids.rb is not loaded by the Metacrunchfile; it runs by path only\n"],
                   [code, stderr]
    end
  end

  def test_notes_a_path_the_metacrunchfile_does_not_load
    in_project do
      assert_equal "note: tools/fix.rb is not loaded by the Metacrunchfile; it runs by path only\n",
                   cli("generate", "job", "tools/fix.rb")[2]
    end
  end

  def test_warns_about_a_path_that_declares_a_name_twice
    in_project("jobs/fix.rb" => %(Metacrunch.job("fix") { source [] }\n)) do
      assert_equal "warning: fix is declared more than once (jobs/fix.rb, jobs/more/fix.rb); rename one\n",
                   cli("generate", "job", "jobs/more/fix.rb")[2]
    end
  end

  def test_warns_about_a_new_file_that_does_not_load
    in_project do
      broken = ->(target, **) { Metacrunch::Generators::Plan.new.add(target.file, "raise \"broken\"\n") }
      _code, _stdout, stderr = override(Metacrunch::Generators::Files, :plan, broken) do
        cli("generate", "job", "catalog:ids")
      end

      assert_equal "warning: jobs/catalog/ids.rb: RuntimeError: broken\n", stderr
    end
  end

  def test_warns_when_the_metacrunchfile_above_a_path_fails
    in_project("Metacrunchfile" => "raise \"broken\"\n") do |root|
      code, _stdout, stderr = cli("generate", "job", "tools/fix.rb")

      assert_equal [0, "warning: could not load #{root}/Metacrunchfile: RuntimeError: broken; " \
                       "tools/fix.rb is not checked\n"], [code, stderr]
    end
  end

  def test_help_lists_the_kinds
    _code, stdout, = cli("help", "generate")

    assert_match(%r{^Kinds:\n  job +jobs/NAME\.rb: reads JSON Lines from stdin}, stdout)
    assert_match(/--\[no-\]test +Create a test \(default: for a NAME\)/, stdout)
  end

  def test_generate_is_a_reserved_name
    assert Metacrunch::Names.reserved?("generate")
  end

  USAGE_ERRORS.each_with_index do |(args, message), index|
    define_method("test_usage_error_#{index}") do
      in_project do |root|
        code, _stdout, stderr = cli("generate", *args)

        assert_equal [2, "Error: #{message}"], [code, stderr.lines.first.chomp]
        assert_empty Dir.glob("**/*.rb", base: root)
      end
    end
  end

  private

  def in_tmpdir
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield File.realpath(dir) } }
  end

  # A project in a temporary directory, the working directory while the
  # block runs; files: path => code (a frozen string comment is added).
  def in_project(files = {})
    in_tmpdir do |root|
      {"Metacrunchfile" => METACRUNCHFILE}.merge(files).each do |path, code|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# frozen_string_literal: true\n\n#{code}")
      end
      yield root
    end
  end

end
