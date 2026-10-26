# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# Runs every example as a user would, through metacrunch's executable.
class ExamplesTest < Minitest::Test

  include Helpers

  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_report
    path = File.join(@dir, "report.xlsx")
    _stdout, stderr, status = metacrunch("run", example("report.rb"), "--target", path, example("data/books.jsonl"))

    assert_predicate status, :success?, stderr
    assert_equal ["Nr.", "Titel", "Jahr", "Exemplare", "Verfügbar"], rows(path).first
    assert_equal ["00124", "Cataloging, step by step", 2019, 0, false], rows(path)[2]
  end

  private

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, *)

end
