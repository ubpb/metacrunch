# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Generates a project and files as a user would, then runs what was
# generated: the jobs through exe/metacrunch, the generated tests in one
# process, RuboCop over all of it.
class ExeGeneratorsTest < Minitest::Test

  include CliHelper

  ROOT = File.expand_path("../..", __dir__)
  LIB = File.join(ROOT, "lib")
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil}.freeze
  RECORDS = %({"id":1,"title":"A"}\n{"title":"B"}\n)
  KEPT = [{"id" => 1, "title" => "A"}].freeze
  # The sections of metacrunch --help, each with what was generated.
  HELP = /^Jobs .*\n  catalog:ids.*^Transforms .*\n  catalog:clean.*^Project commands .*\n  catalog:re-index/m
  BY_NAME = [["job", "catalog:ids"], ["transform", "catalog:clean"], ["command", "catalog:re-index"],
             ["source", "files:lines"], ["sink", "files:json"]].freeze
  BY_PATH = [["job", "tools/fix"], ["transform", "tools/tidy"], ["command", "tools/publish"],
             ["source", "tools/lines"], ["sink", "tools/json_file"]].freeze

  def test_a_new_project_lists_and_runs_what_was_generated
    in_tmpdir do |dir|
      root = generate_project(dir)
      help, = metacrunch("--help", chdir: root)
      outputs = ["catalog:ids", "catalog:clean"].map { metacrunch(it, stdin: RECORDS, chdir: root).first }
      _stdout, log, status = metacrunch("catalog:re-index", chdir: root)

      assert_match HELP, help
      assert_equal([KEPT, KEPT], outputs.map { |out| out.lines.map { JSON.parse(it) } })
      assert_equal [true, true], [status.success?, log.include?("catalog:re-index: nothing to do yet")]
    end
  end

  # The job uses the transform, and the tests start outside the project,
  # so the names of use must resolve in PROJECT.
  def test_the_generated_tests_of_a_project_pass_in_one_run
    in_tmpdir do |dir|
      root = generate_project(dir)
      job = File.join(root, "jobs/catalog/ids.rb")
      File.write(job, File.read(job).sub(%(  # use "catalog:clean", lang: "en"\n), %(  use "catalog:clean"\n)))
      stdout, stderr, status = run_tests(root, from: dir)

      assert_equal [true, ""], [status.success?, stderr], stdout
      assert_match(/^6 runs, \d+ assertions, 0 failures, 0 errors/, stdout)
    end
  end

  def test_files_by_path_run_and_pass_their_tests_without_project
    in_tmpdir do |dir|
      generate_paths(dir)
      fixed, = metacrunch("run", "tools/fix.rb", stdin: RECORDS, chdir: dir)
      stdout, stderr, status = run_tests(dir)

      assert_equal(KEPT, fixed.lines.map { JSON.parse(it) })
      assert_equal [true, ""], [status.success?, stderr], stdout
      assert_match(/^5 runs, \d+ assertions, 0 failures, 0 errors/, stdout)
    end
  end

  def test_generated_files_pass_rubocop
    in_tmpdir do |dir|
      generate_project(dir)
      generate_paths(File.join(dir, "loose").tap { FileUtils.mkdir_p(it) })
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, Gem.bin_path("rubocop", "rubocop"), "--config",
                                              File.join(ROOT, ".rubocop.yml"), "--cache", "false", "--format",
                                              "simple", chdir: dir)

      assert_predicate status, :success?, stdout + stderr
      assert_match(/\b\d+ files inspected, no offenses detected/, stdout)
    end
  end

  private

  # catalog/ in dir with the five kinds by name, generated from
  # catalog/jobs/, a directory below the root. Returns the root.
  def generate_project(dir)
    Dir.chdir(dir) { generate("new", "catalog") }
    root = File.join(dir, "catalog")
    Dir.chdir(File.join(root, "jobs")) { BY_NAME.each { |kind, name| generate("generate", kind, name) } }
    root
  end

  # The five kinds by path with tests, in dir.
  def generate_paths(dir)
    Dir.chdir(dir) { BY_PATH.each { |kind, path| generate("generate", kind, "--test", path) } }
  end

  def generate(*args)
    code, _stdout, stderr = cli(*args)
    raise "metacrunch #{args.join(" ")} failed (#{code}): #{stderr}" unless code.zero?
  end

  # Runs the tests below dir/test in one process, started in from, with
  # warnings on as rake test has them.
  def run_tests(dir, from: dir)
    tests = Dir.glob(File.join(dir, "test/**/*_test.rb"))
    Open3.capture3(CLEAN_ENV, RbConfig.ruby, "-w", "-I", LIB, "-e", "ARGV.each { require it }", *tests, chdir: from)
  end

  def metacrunch(*, chdir:, stdin: "")
    command = [RbConfig.ruby, "-I", LIB, File.join(ROOT, "exe", "metacrunch"), *]
    Open3.capture3(CLEAN_ENV, *command, stdin_data: stdin, chdir:)
  end

  def in_tmpdir
    Dir.mktmpdir { |dir| yield File.realpath(dir) }
  end

end
