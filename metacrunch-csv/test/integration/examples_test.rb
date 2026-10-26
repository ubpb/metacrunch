# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# Runs every example as a user would, through metacrunch's executable.
class ExamplesTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def test_csv2jsonl
    stdout, stderr, status = metacrunch("run", example("csv2jsonl.rb"), example("data/books.csv"))
    records = stdout.lines.map { JSON.parse(it) }

    assert_predicate status, :success?, stderr
    assert_equal([2004, 2019, nil, 1998], records.map { it["year"] })
    assert_equal(["0838908829", "", "0306406152", ""], records.map { it["isbn"] })
  end

  def test_books2excel
    Dir.mktmpdir do |dir|
      output = File.join(dir, "books.csv")
      _stdout, stderr, status = metacrunch("run", example("books2excel.rb"), "--target", output,
                                           example("data/books.csv"))

      lines = File.binread(output).lines

      assert_predicate status, :success?, stderr
      assert_equal ["Nr.;Titel;Jahr\n", "4;M\xFCller's guide to indexing;1998\n".b], lines.values_at(0, 4)
    end
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, *)

end
