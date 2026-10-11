# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "shellwords"
require "tmpdir"

# Runs every example as a user would, through exe/metacrunch, so the
# examples keep working.
class ExamplesTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  EXAMPLES = File.join(ROOT, "examples")

  def test_hello_greets_on_stdout
    stdout, stderr, status = metacrunch("run", example("hello.rb"))
    greetings = stdout.lines.map { JSON.parse(it)["greeting"] }

    assert_predicate status, :success?, stderr
    assert_equal ["Hello, Ada!", "Hello, Grace!", "Hello, Linus!"], greetings
  end

  def test_catalog_writes_records_rejects_and_errors
    Dir.mktmpdir do |dir|
      _stdout, stderr, status = metacrunch("run", example("catalog.rb"), "--output", dir, example("data/catalog.json"))
      counts = ["records", "rejects", "errors"].map { File.readlines(File.join(dir, "#{it}.jsonl")).size }

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

  def test_the_example_tests_pass
    arguments = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), example("test/catalog_test.rb")]
    stdout, stderr, status = Open3.capture3(*arguments)

    assert_predicate status, :success?, stdout + stderr
    assert_match(/ 0 failures, 0 errors/, stdout)
  end

  private

  # Runs sanitize.rb and returns its output, rejects, errors and issues files.
  def sanitize(dir, name, *options)
    files = ["out.jsonl", "rejects.jsonl", "errors.jsonl", "issues.tsv"].map { File.join(dir, "#{name}.#{it}") }
    arguments = ["run", *options, "-i", example("data/publications.jsonl"), "--rejects", files[1], "--errors", files[2],
                 example("sanitize.rb"), "--output", files[0], "--issues", files[3]]
    _stdout, stderr, status = metacrunch(*arguments)
    raise "sanitize.rb failed (#{status.exitstatus}): #{stderr}" unless status.exitstatus == 3

    files.map { File.read(it) }
  end

  def metacrunch(*, stdin_data: "")
    Open3.capture3(*command(*), stdin_data:)
  end

  def command(*)
    [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *]
  end

  def example(path) = File.join(EXAMPLES, path)

end
