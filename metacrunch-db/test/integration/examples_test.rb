# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# Runs the example project as a user would, through metacrunch's executable, with its params file: in a copy, since
# its SQLite files are written into the directory the commands run in.
class ExamplesTest < Minitest::Test

  EXAMPLES = File.expand_path("../../examples", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def setup
    @dir = Dir.mktmpdir
    FileUtils.cp_r("#{EXAMPLES}/.", @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_load_upserts_deletes_and_sends_a_refused_book_to_the_failures_file
    run!("books:setup")
    _, stderr, status = metacrunch("books:load")

    assert_equal 3, status.exitstatus, stderr
    assert_equal(["9780199535569"], File.readlines(File.join(@dir, "failures.jsonl")).map { isbn_of(it) })
    assert_equal 4, rows("books.db")
  end

  def test_export_writes_json_lines_with_iso_dates
    run!("books:setup")
    metacrunch("books:load")
    books = run!("books:export", "--since", "1850").lines.map { JSON.parse(it) }

    assert_equal(["9780140449136", "9780141439600"], books.map { it["isbn"] })
    assert_equal Date.today.iso8601, books.first["added_on"]
  end

  def test_copy_fills_the_second_database
    run!("books:setup")
    metacrunch("books:load")
    run!("books:setup", "--url", "sqlite://books-copy.db")
    run!("books:copy")

    assert_equal 4, rows("books-copy.db")
  end

  private

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, "run", "--params", "params.yml", *, chdir: @dir)

  def run!(*)
    stdout, stderr, status = metacrunch(*)

    assert_predicate status, :success?, stderr
    stdout
  end

  def isbn_of(line) = JSON.parse(line).dig("record", "isbn")

  def rows(file) = Metacrunch::Db::Connection.new(url: "sqlite://#{@dir}/#{file}").connect { it[:books].count }

end
