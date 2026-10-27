# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "open3"
require "openssl"
require "shellwords"
require "tmpdir"

# Runs every example as a user would, through exe/metacrunch, so the
# examples keep working.
class ExamplesTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  EXAMPLES = File.join(ROOT, "examples")
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil,
               "PSEUDONYM_PEPPER" => nil}.freeze

  def test_hello_greets_on_stdout
    stdout, stderr, status = metacrunch("run", example("hello.rb"))
    greetings = stdout.lines.map { JSON.parse(it)["greeting"] }

    assert_predicate status, :success?, stderr
    assert_equal ["Hello, Ada!", "Hello, Grace!", "Hello, Linus!"], greetings
  end

  def test_catalog_writes_records_rejects_and_errors
    Dir.mktmpdir do |dir|
      _stdout, stderr, status = metacrunch("run", example("catalog.rb"), "--output", dir, example("data/catalog.json"))
      counts = ["records", "rejects", "failures"].map { File.readlines(File.join(dir, "#{it}.jsonl")).size }

      assert_equal 3, status.exitstatus, stderr
      assert_equal [7, 2, 1], counts
    end
  end

  def test_catalog_can_be_traced
    Dir.mktmpdir do |dir|
      stdout, stderr, status = metacrunch("trace", "-n", "2", example("catalog.rb"), "--output", dir,
                                          example("data/catalog.json"))

      assert_predicate status, :success?, stderr
      assert_match(/^#2 /, stdout)
    end
  end

  def test_normalize_works_in_a_pipe_behind_another_job
    pipeline = [Shellwords.join(command("run", example("hello.rb"))),
                Shellwords.join(command("run", example("normalize.rb")))].join(" | ")
    stdout, stderr, status = Open3.capture3("sh", "-c", pipeline)

    assert_predicate status, :success?, stderr
    assert_equal 3, stdout.lines.size
  end

  def test_normalize_tidies_records_from_stdin
    input = File.read(example("data/publications.jsonl"))
    stdout, stderr, status = metacrunch("run", example("normalize.rb"), stdin_data: input)
    titles = stdout.lines.filter_map { JSON.parse(it)["title"] }

    assert_predicate status, :success?, stderr
    assert_equal 192, titles.size
    assert(titles.none? { it.include?("  ") || it != it.strip })
  end

  def test_sanitize_writes_the_same_files_with_workers
    Dir.mktmpdir do |dir|
      inline = sanitize(dir, "inline")
      forked = sanitize(dir, "forked", "-w", "2")

      assert_equal inline, forked
      assert_equal([187, 8, 5], inline.first(3).map { it.lines.size })
    end
  end

  def test_pseudonymize_replaces_every_author_with_a_pseudonym
    stdout, stderr, status = pseudonymize
    authors = stdout.lines.flat_map { JSON.parse(it)["authors"] }

    assert_predicate status, :success?, stderr
    assert_equal 400, authors.size
    assert_empty authors.grep_v(/\Aauthor-\h{12}\z/)
  end

  def test_pseudonymize_gives_one_pseudonym_per_name
    input = File.readlines(example("data/publications.jsonl")).map { JSON.parse(it)["authors"] }
    output = pseudonymize.first.lines.map { JSON.parse(it)["authors"] }
    pairs = input.flatten.map { it.split.join(" ") }.zip(output.flatten).uniq

    assert_equal ["Doe, Jane", "Poe, Edgar", "Roe, Richard"], pairs.map(&:first).sort
    assert_equal 3, pairs.map(&:last).uniq.size
  end

  def test_pseudonymize_takes_the_pepper_from_a_variable_in_the_container_environment
    stdout, = pseudonymize("-e", "container", "--params", example("credentials/params.yml"),
                           env: {"PSEUDONYM_PEPPER" => "another pepper"})
    expected = "author-#{OpenSSL::HMAC.hexdigest("SHA256", "another pepper", "Doe, Jane")[0, 12]}"

    assert_equal expected, JSON.parse(stdout.lines.first)["authors"].first
    refute_equal expected, JSON.parse(pseudonymize.first.lines.first)["authors"].first
  end

  def test_pseudonymize_takes_the_pepper_from_the_credentials_with_the_params_file_and_no_environment
    stdout, stderr, status = pseudonymize("--params", example("credentials/params.yml"))

    assert_predicate status, :success?, stderr
    assert_equal pseudonymize.first, stdout
  end

  def test_the_example_tests_pass
    arguments = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), example("test/catalog_test.rb")]
    stdout, stderr, status = Open3.capture3(*arguments)

    assert_predicate status, :success?, stdout + stderr
    assert_match(/ 0 failures, 0 errors/, stdout)
  end

  def test_project_release_switches_current_only_after_a_clean_run
    Dir.mktmpdir do |dir|
      project = File.join(dir, "project")
      FileUtils.cp_r(example("project"), project)
      _stdout, stderr, status = metacrunch("run", "catalog:release", chdir: File.join(project, "jobs"))
      current = File.join(project, "out", "current", "titles.jsonl")
      released = File.readlines(current).size
      failed = metacrunch("run", "catalog:release", "--input", File.join(project, "data", "broken.jsonl"),
                          chdir: project)

      assert_equal [0, 4], [status.exitstatus, released], stderr
      assert_equal 3, failed.last.exitstatus
      assert_equal 4, File.readlines(current).size
    end
  end

  def test_project_help_lists_the_job_and_the_command
    stdout, stderr, status = metacrunch("--help", chdir: example("project"))

    assert_predicate status, :success?, stderr
    assert_match(/^  catalog +Write the public titles into a directory$/, stdout)
    assert_match(%r{^  catalog:release +Write a new release and switch out/current to it$}, stdout)
  end

  def test_project_help_lists_the_transform
    stdout, stderr, status = metacrunch("--help", chdir: example("project"))

    assert_predicate status, :success?, stderr
    assert_match(/^Transforms \(.*\):\n  catalog:public +Keep the public titles, reduced to some fields$/, stdout)
  end

  def test_project_jobs_share_the_transform_with_other_values
    stdout, stderr, status = metacrunch("run", "catalog:ids", chdir: example("project"))

    assert_predicate status, :success?, stderr
    assert_equal([{"id" => "t1"}, {"id" => "t2"}, {"id" => "t4"}, {"id" => "t5"}], stdout.lines.map { JSON.parse(it) })
  end

  def test_the_project_example_tests_pass
    tests = Dir[example("project/test/**/*_test.rb")]
    arguments = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", "ARGV.each { require it }", *tests]
    stdout, stderr, status = Open3.capture3(*arguments)

    assert_equal 5, tests.size
    assert_predicate status, :success?, stdout + stderr
    assert_match(/ 0 failures, 0 errors/, stdout)
  end

  private

  # Runs sanitize.rb and returns its output, rejects, errors and issues files.
  def sanitize(dir, name, *options)
    files = ["out.jsonl", "rejects.jsonl", "failures.jsonl", "issues.tsv"].map { File.join(dir, "#{name}.#{it}") }
    arguments = ["run", *options, "-i", example("data/publications.jsonl"), "--rejects", files[1],
                 "--failures", files[2], example("sanitize.rb"), "--output", files[0], "--issues", files[3]]
    _stdout, stderr, status = metacrunch(*arguments)
    raise "sanitize.rb failed (#{status.exitstatus}): #{stderr}" unless status.exitstatus == 3

    files.map { File.read(it) }
  end

  def pseudonymize(*options, env: {})
    metacrunch("run", *options, "-i", example("data/publications.jsonl"), example("credentials/pseudonymize.rb"), env:)
  end

  def metacrunch(*, stdin_data: "", env: {}, chdir: Dir.pwd)
    Open3.capture3(CLEAN_ENV.merge(env), *command(*), stdin_data:, chdir:)
  end

  def command(*)
    [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *]
  end

  def example(path) = File.join(EXAMPLES, path)

end
