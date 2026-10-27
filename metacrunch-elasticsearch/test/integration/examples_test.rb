# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# Runs the examples as a user would, through metacrunch's executable, against the Elasticsearch of the integration
# tests, connected by the params files of the examples, which read the ELASTICSEARCH_* variables.
class ExamplesTest < Minitest::Test

  include Integration

  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def test_load_sends_a_refused_book_to_the_failures_file
    create_index
    Dir.mktmpdir do |dir|
      failures = File.join(dir, "failures.jsonl")
      _, stderr, status = metacrunch("run", "--params", example("params.yml"), example("load.rb"), "--index", @index,
                                     "--failures", failures, example("data/books.jsonl"))

      assert_equal 3, status.exitstatus, stderr
      assert_equal(["9780140449266"], File.readlines(failures).map { JSON.parse(it).dig("record", "isbn") })
    end
  end

  def test_export_writes_what_a_query_string_matches
    create_index
    index_documents([{"id" => "1", "title" => "Faust", "lang" => "de"},
                     {"id" => "2", "title" => "Emma", "lang" => "en"}])
    stdout, stderr, status = metacrunch("run", "--params", example("params.yml"), example("export.rb"),
                                        "--index", @index, "--query", "lang:de")
    titles = stdout.lines.map { JSON.parse(it)["title"] }

    assert_predicate status, :success?, stderr
    assert_equal ["Faust"], titles
  end

  def test_the_project_rebuilds_behind_an_alias_and_lists_its_indices
    books = "#{@index}-books"
    _, stderr, status = in_project("books:rebuild", "--alias", books)

    assert_predicate status, :success?, stderr
    assert_equal 5, stored(books).size
    stdout, stderr, = in_project("es:list", "#{books}-*")

    assert_match(/\A#{books}-\d{8}-\d{6}  #{books}  5 /, stdout.lines[1].to_s, stderr)
  end

  def test_a_rebuild_that_fails_deletes_its_index_and_leaves_the_alias
    books = "#{@index}-books"
    Dir.mktmpdir do |dir|
      input = File.join(dir, "bad.jsonl").tap { File.write(it, %({"isbn":"1","title":"A","year":"unknown"}\n)) }
      _, stderr, status = in_project("books:rebuild", "--alias", books, "--input", input)

      assert_equal 1, status.exitstatus, stderr
    end

    assert_empty client.cat.indices(index: "#{books}-*", format: "json").body
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*, chdir: ROOT) = Open3.capture3(RbConfig.ruby, BIN, *, chdir:)

  # Runs a job or command of the project with its params file.
  def in_project(name, *) = metacrunch("run", "--params", "params.yml", name, *, chdir: example("project"))

end
