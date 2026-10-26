# frozen_string_literal: true

require "test_helper"
require "json"
require "logger"
require "metacrunch/testing"

class JobsTest < Minitest::Test

  include Fixtures
  include Iso

  Marc = Metacrunch::Marc
  INPUTS = {xml: "collection.xml", iso2709: "collection.mrc", json: "collection.jsonl"}.freeze
  PAIRS = [[:xml, :iso2709], [:iso2709, :xml], [:json, :iso2709]].freeze
  # The last step of a job that sends record Strings back from the workers.
  SERIALIZE = {
    xml: ->(record) { record.to_xml(namespace: false) },
    iso2709: lambda(&:to_iso2709),
    json: lambda(&:to_json)
  }.freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_same_output_with_and_without_workers_and_parsing
    runs = [nil, 2].product([true, false])
    marked = ["processed"] * 3

    PAIRS.each do |input, output|
      outputs = runs.map { |workers, parse| run_job(input, output, workers:, parse:) }

      assert_equal 1, outputs.uniq.size, "#{input} to #{output}"
      assert_equal(marked, read(outputs.first).map { it.value("999", "a") })
    end
  end

  def test_serializing_iso2709_and_json_in_the_workers_gives_the_same_bytes
    [[:xml, :iso2709], [:json, :iso2709], [:iso2709, :json]].each do |input, output|
      serialized = run_job(input, output, workers: 2, parse: false, serialize: true)

      assert_equal run_job(input, output, workers: nil, parse: true), serialized, "#{input} to #{output}"
    end
  end

  def test_serializing_marcxml_in_the_workers_gives_the_same_records
    serialized = run_job(:iso2709, :xml, workers: 2, parse: false, serialize: true)
    plain = run_job(:iso2709, :xml, workers: nil, parse: true)

    assert_equal read(plain).map(&:fields), read(serialized).map(&:fields)
  end

  def test_a_broken_record_fails_alone_in_every_format
    xml = %(<collection><record><controlfield tag="001">1</controlfield></record>) +
          %(<record><controlfield tag="001">2</record></collection>)

    {
      "broken.xml" => xml,
      "broken.mrc" => book("1") + book("2").sub("Title", "Ti\x1Etle"),
      "broken.jsonl" => %({"fields": [{"001": "1"}]}\n{"fields": [{"001": 2}]}\n)
    }.each do |name, content|
      result = Metacrunch::Testing.run(skipping_job(write(name, content)))

      assert_equal :ok_with_failures, result.status, name
      assert_equal 1, result.records.size, name
      assert_equal "source", result.failures.first.last.step, name
    end
  end

  def test_a_record_iso2709_cannot_hold_fails_alone_in_a_step
    output = File.join(@dir, "out.mrc")
    inputs = [fixture_path("collection.xml"), fixture_path("local.xml")]
    job = Metacrunch.job do
      source Marc::Reader.new(inputs)
      on_failure :skip
      map(name: "serialize", &:to_iso2709)
      sink Marc::Writer.new(output, format: :iso2709)
    end

    status = job.run(logger: Logger.new(nil)).status
    ids = Marc::Iso2709.each(File.binread(output)).map { it["001"].value }

    assert_equal :ok_with_failures, status
    assert_equal ["book-1", "article-1", "holding-1"], ids
  end

  def test_a_record_iso2709_cannot_hold_stops_the_run_in_the_sink
    output = File.join(@dir, "out.mrc")
    input = fixture_path("local.xml")
    job = Metacrunch.job do
      source Marc::Reader.new(input)
      sink Marc::Writer.new(output, format: :iso2709)
    end
    result = job.run(logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_match(/record at position \d+ cannot be written as ISO 2709: field 852H/, result.error.to_s)
  end

  def test_testing_run_with_parsed_records
    job = Metacrunch.job do
      map { {"id" => it["001"].value, "title" => it.value("245", "a")} }
    end
    source = Marc::Iso2709.each(File.binread(fixture_path("collection.mrc"))).to_a

    [nil, 2].each do |workers|
      result = Metacrunch::Testing.run(job, source:, workers:)

      assert_equal({"id" => "book-1", "title" => "Metadata in practice"}, result.records.first)
    end
  end

  def test_an_aborted_run_leaves_a_well_formed_file
    input = fixture_path("collection.xml")
    output = File.join(@dir, "out.xml")
    job = Metacrunch.job do
      source Marc::Reader.new(input)
      map { it["001"].value == "article-1" ? raise("broken") : it }
      sink Marc::Writer.new(output, format: :xml)
    end
    result = job.run(logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_equal(["book-1"], Marc::Xml.each(File.read(output)).map { it["001"].value })
  end

  private

  # Reads input in the format of input, adds a field 999 and writes output.
  # parse: false parses in a step; serialize: true serializes in a step.
  def run_job(input, output, workers:, parse:, serialize: false)
    path = fixture_path(INPUTS.fetch(input))
    target = File.join(@dir, "out-#{input}-#{output}-#{workers}-#{parse}-#{serialize}")
    serializer = SERIALIZE.fetch(output)
    job = Metacrunch.job do
      source Marc::Reader.new(path, parse:)
      map(name: "parse") { Marc.parse(it) } unless parse
      map(name: "mark") { it.add(Marc::DataField.new("999", " ", " ", [["a", "processed"]])) }
      map(name: "serialize") { serializer.call(it) } if serialize
      sink Marc::Writer.new(target, format: output)
    end
    result = job.run(workers:, logger: Logger.new(nil))

    assert_equal :ok, result.status, result.error
    File.binread(target)
  end

  def skipping_job(path)
    Metacrunch.job do
      source Marc::Reader.new(path)
      on_failure :skip
    end
  end

  def read(string) = Marc::Reader.new(StringIO.new(string)).each.to_a

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
