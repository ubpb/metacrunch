# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsTargetTest < Minitest::Test

  Target = Metacrunch::Generators::Target
  ROOT = Pathname("/work/catalog")
  CWD = "/work/catalog/jobs"

  # kind, name => file, test, test class (below ROOT)
  NAMES = {
    ["job", "catalog:ids"] => ["jobs/catalog/ids.rb", "test/jobs/catalog/ids_test.rb", "CatalogIdsJobTest"],
    ["transform", "clean"] => ["transforms/clean.rb", "test/transforms/clean_test.rb", "CleanTransformTest"],
    ["command", "es:create-index"] => ["commands/es/create_index.rb", "test/commands/es/create_index_test.rb",
                                       "EsCreateIndexCommandTest"],
    ["job", "2go"] => ["jobs/2go.rb", "test/jobs/2go_test.rb", "Job2goTest"],
    ["source", "marc:dump"] => ["lib/marc/dump.rb", "test/lib/marc/dump_test.rb", "MarcDumpTest"],
    ["sink", "a:b:json_array"] => ["lib/a/b/json_array.rb", "test/lib/a/b/json_array_test.rb", "ABJsonArrayTest"]
  }.freeze

  # kind, path => file, test (relative to CWD), name, test class
  PATHS = {
    ["job", "tools/fix"] => ["tools/fix.rb", "test/fix_test.rb", "fix", "FixJobTest"],
    ["command", "../release.rb"] => ["../release.rb", "test/release_test.rb", "release", "ReleaseCommandTest"],
    ["sink", "lib/json_array.rb"] => ["lib/json_array.rb", "test/json_array_test.rb", "json_array", "JsonArrayTest"]
  }.freeze

  # kind, argument, root => message
  ERRORS = {
    ["job", "Catalog", ROOT] =>
      '"Catalog" is not a valid job name; use a-z, 0-9, _ and -, in parts separated by :',
    ["command", "run", ROOT] => '"run" is the name of a built-in command; choose another name',
    ["job", "jobs/MyJob.rb", nil] => 'MyJob.rb: "MyJob" is not a valid job name; use a-z, 0-9, _ and -',
    ["transform", "x/check.rb", nil] =>
      'check.rb: "check" is the name of a built-in command; choose another file name',
    ["source", "marc-dump", ROOT] =>
      '"marc-dump" is not a valid source name; use a-z, 0-9 and _, starting with a letter, in parts separated by :',
    ["sink", "a:2b", ROOT] =>
      '"a:2b" is not a valid sink name; use a-z, 0-9 and _, starting with a letter, in parts separated by :',
    ["sink", "lib/2b.rb", nil] => '2b.rb: "2b" is not a valid sink name; use a-z, 0-9 and _, starting with a letter',
    ["sink", "file", ROOT] => '"file" would reopen File; choose another name',
    ["source", "file:reader", ROOT] => '"file:reader" would reopen File; choose another name',
    ["source", "lib/dir.rb", nil] => '"dir" would reopen Dir; choose another name',
    ["sink", "metacrunch:job:x", ROOT] => '"metacrunch:job:x" would reopen Metacrunch::Job; choose another name',
    ["source", "metacrunch:json_lines", ROOT] =>
      '"metacrunch:json_lines" would reopen Metacrunch::JsonLines; choose another name',
    ["sink", "json", ROOT] => '"json" would shadow require "json"; choose another name',
    ["source", "yaml", ROOT] => '"yaml" would shadow require "yaml"; choose another name',
    ["source", "rake:lines", ROOT] => '"rake:lines" would shadow require "rake/lines"; choose another name',
    ["job", "jobs/", nil] => "jobs/ is a directory; give a file name",
    ["job", "catalog:ids", nil] => "no Metacrunchfile found in /work/catalog/jobs or above; give a path " \
                                   "(./ids.rb) or create a project with metacrunch new"
  }.freeze

  NAMES.each do |(kind, name), (file, test, test_class)|
    define_method("test_#{kind}_#{name.tr(":-", "__")}_goes_below_the_root") do
      target = Target.for(kind, name, cwd: CWD, root: ROOT)

      assert_equal [ROOT.join(file).to_s, ROOT.join(test).to_s, test_class],
                   [target.file, target.test, target.test_class]
      assert_equal [:name, name, name, ROOT], [target.form, target.argument, target.name, target.root]
    end
  end

  PATHS.each do |(kind, path), (file, test, name, test_class)|
    define_method("test_#{kind}_path_#{name}_stays_where_it_is_given") do
      target = Target.for(kind, path, cwd: CWD, root: ROOT)

      assert_equal [File.expand_path(file, CWD), File.expand_path(test, CWD), name, test_class],
                   [target.file, target.test, target.name, target.test_class]
      assert_equal [:path, nil], [target.form, target.root]
    end
  end

  ERRORS.each_with_index do |((kind, argument, root), message), index|
    define_method("test_error_#{index}_#{kind}") do
      error = assert_raises(Metacrunch::UsageError) { Target.for(kind, argument, cwd: CWD, root:) }

      assert_equal message, error.message
    end
  end

  def test_a_path_keeps_its_argument_with_rb
    assert_equal "tools/fix.rb", Target.for("job", "tools/fix", cwd: CWD, root: nil).argument
  end

  def test_sources_and_sinks_are_constants_in_modules
    target = Target.for("source", "a:b:json_array", cwd: CWD, root: ROOT)

    assert_equal [["A", "B"], "JsonArray", "A::B::JsonArray"], [target.modules, target.class_name, target.constant]
    refute_predicate target, :declared?
  end

  def test_a_path_gives_a_class_without_modules
    target = Target.for("source", "lib/json_array.rb", cwd: CWD, root: nil)

    assert_equal [[], "JsonArray"], [target.modules, target.class_name]
  end

  def test_jobs_transforms_and_commands_have_no_constant
    target = Target.for("command", "catalog:release", cwd: CWD, root: ROOT)

    assert_equal [[], nil], [target.modules, target.class_name]
    assert_predicate target, :declared?
  end

  def test_a_source_must_not_reopen_a_module_of_the_project
    in_project("lib/marc/dump.rb" => "module Marc\n  class Dump; end\nend\n") do |root|
      error = assert_raises(Metacrunch::UsageError) { Target.for("source", "marc", cwd: root.to_s, root:) }

      assert_equal '"marc" would reopen Marc of lib/marc/dump.rb; choose another name', error.message
    end
  end

  def test_a_sink_must_not_go_into_a_class_of_the_project
    in_project("lib/marc.rb" => "class Marc; end\n") do |root|
      error = assert_raises(Metacrunch::UsageError) { Target.for("sink", "marc:dump", cwd: root.to_s, root:) }

      assert_equal '"marc:dump" would reopen Marc of lib/marc.rb; choose another name', error.message
    end
  end

  def test_a_source_may_go_into_a_module_of_the_project_or_replace_itself
    files = {"lib/marc.rb" => "module Marc; end\n", "lib/marc/dump.rb" => "module Marc\n  class Dump; end\nend\n"}

    in_project(files) do |root|
      assert_equal "Marc::Dump", Target.for("source", "marc:dump", cwd: root.to_s, root:).constant
    end
  end

  def test_a_source_may_go_into_an_existing_module
    assert_equal "Metacrunch::Lines", Target.for("source", "metacrunch:lines", cwd: CWD, root: ROOT).constant
  end

  private

  # A project root in a temporary directory with files (path => code).
  def in_project(files)
    Dir.mktmpdir do |dir|
      root = Pathname(File.realpath(dir))
      files.each { |path, code| FileUtils.mkdir_p(root.join(path).dirname).then { File.write(root.join(path), code) } }
      yield root
    end
  end

end
