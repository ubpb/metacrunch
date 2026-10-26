# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# Runs every example as a user would, through metacrunch's executable.
class ExamplesTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def test_marcxml2jsonl
    stdout, stderr, status = metacrunch("run", example("marcxml2jsonl.rb"), example("data/catalog.xml"))
    records = stdout.lines.map { JSON.parse(it) }

    assert_predicate status, :success?, stderr
    assert_equal(["book-1", "article-1", "holding-1"], records.map { it["id"] })
    assert_equal "Metadata in practice : a handbook", records.first["title"]
  end

  def test_cleanup_writes_marcxml
    Dir.mktmpdir do |dir|
      output = File.join(dir, "clean.xml")
      _stdout, stderr, status = metacrunch("run", example("cleanup.rb"), "--target", output,
                                           example("data/catalog.xml"))
      records = Metacrunch::Marc::Xml.each(File.read(output)).to_a

      assert_predicate status, :success?, stderr
      assert(records.all? { it.value("883", "a") == "metacrunch cleanup example" })
      assert_empty(records.flat_map { it.fields("856", ind2: "2") })
    end
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, *)

end
