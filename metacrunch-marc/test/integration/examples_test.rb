# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# Runs every example as a user would, through metacrunch's executable.
class ExamplesTest < Minitest::Test

  Marc = Metacrunch::Marc
  ROOT = File.expand_path("../..", __dir__)
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def test_marc2jsonl_reads_every_format
    outputs = ["catalog.xml", "catalog.mrc", "catalog.jsonl"].map do |name|
      stdout, stderr, status = metacrunch("run", example("marc2jsonl.rb"), example("data/#{name}"))

      assert_predicate status, :success?, stderr
      stdout
    end

    assert_equal 1, outputs.uniq.size
    assert_equal("Metadata in practice : a handbook", JSON.parse(outputs.first.lines.first)["title"])
  end

  def test_cleanup_writes_every_format
    Dir.mktmpdir do |dir|
      ["xml", "iso2709", "json"].each do |to|
        output = File.join(dir, "clean.#{to}")
        _stdout, stderr, status = metacrunch("run", example("cleanup.rb"), "--to", to, "--target", output,
                                             example("data/catalog.xml"))
        records = Marc::Reader.new(output).each.to_a

        assert_predicate status, :success?, stderr
        assert(records.all? { it.value("883", "a") == "metacrunch cleanup example" }, "--to #{to}")
        assert_empty(records.flat_map { it.fields("856", ind2: "2") }, "--to #{to}")
      end
    end
  end

  def test_convert_through_every_format
    Dir.mktmpdir do |dir|
      mrc, jsonl, xml = ["catalog.mrc", "catalog.jsonl", "catalog.xml"].map { File.join(dir, it) }
      steps = [["iso2709", example("data/catalog.xml"), mrc], ["json", mrc, jsonl], ["xml", jsonl, xml]]
      steps.each do |to, from, target|
        _stdout, stderr, status = metacrunch("run", example("convert.rb"), "--to", to, "--target", target, from)

        assert_predicate status, :success?, stderr
      end

      assert_equal catalog, Marc::Xml.each(File.read(xml)).map(&:fields)
    end
  end

  def test_convert_with_workers
    stdout, stderr, status = metacrunch("run", "--workers", "2", example("convert.rb"), "--to", "json",
                                        example("data/catalog.mrc"))

    assert_predicate status, :success?, stderr
    assert_equal catalog, Marc::Json.each(stdout).map(&:fields)
  end

  def test_convert_refuses_other_formats
    stdout, stderr, status = metacrunch("run", example("convert.rb"), "--to", "marc", example("data/catalog.xml"))

    refute_predicate status, :success?
    assert_includes stdout + stderr, "format must be :xml, :iso2709 or :json, got :marc"
  end

  private

  def catalog = Marc::Xml.each(File.read(example("data/catalog.xml"))).map(&:fields)

  def example(name) = File.join(ROOT, "examples", name)

  def metacrunch(*) = Open3.capture3(RbConfig.ruby, BIN, *)

end
