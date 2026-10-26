# frozen_string_literal: true

require "test_helper"
require "logger"
require "metacrunch/testing"

class JobsTest < Minitest::Test

  include Fixtures

  Marc = Metacrunch::Marc

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_same_output_with_and_without_workers_and_parsing
    outputs = [nil, 2].product([true, false]).map { |workers, parse| run_marking_job(workers:, parse:) }

    assert_equal 1, outputs.uniq.size
    assert_equal(["processed"] * 3, Marc::Xml.each(outputs.first).map { it.value("999", "a") })
  end

  def test_records_parsed_and_serialized_in_the_workers
    input = fixture_path("collection.xml")
    output = File.join(@dir, "serialized.xml")
    job = Metacrunch.job do
      source Marc::Reader.new(input, parse: false)
      map(name: "parse") { Marc::Xml.parse(it) }
      map(name: "mark") { it.add(Marc::DataField.new("999", " ", " ", [["a", "processed"]])) }
      map(name: "serialize") { it.to_xml(namespace: false) }
      sink Marc::Writer.new(output, format: :xml)
    end

    assert_equal :ok, job.run(workers: 2, logger: Logger.new(nil)).status
    assert_equal Marc::Xml.each(run_marking_job(workers: nil, parse: true)).to_a, Marc::Xml.each(File.read(output)).to_a
  end

  def test_a_broken_record_fails_alone
    path = File.join(@dir, "broken.xml")
    File.write(path, %(<collection><record><controlfield tag="001">1</controlfield></record>) +
                     %(<record><controlfield tag="001">2</record></collection>))
    job = Metacrunch.job do
      source Marc::Reader.new(path)
      on_failure :skip
    end
    result = Metacrunch::Testing.run(job)

    assert_equal :ok_with_failures, result.status
    assert_equal 1, result.records.size
    assert_equal "source", result.failures.first.last.step
  end

  def test_testing_run_with_parsed_records
    job = Metacrunch.job do
      map { {"id" => it["001"].value, "title" => it.value("245", "a")} }
    end
    source = Marc::Xml.each(fixture("collection.xml")).to_a

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

  def run_marking_job(workers:, parse:)
    input = fixture_path("collection.xml")
    output = File.join(@dir, "out-#{workers}-#{parse}.xml")
    job = Metacrunch.job do
      source Marc::Reader.new(input, parse:)
      map(name: "parse") { it.is_a?(String) ? Marc::Xml.parse(it) : it }
      map(name: "mark") { it.add(Marc::DataField.new("999", " ", " ", [["a", "processed"]])) }
      sink Marc::Writer.new(output, format: :xml)
    end
    result = job.run(workers:, logger: Logger.new(nil))

    assert_equal :ok, result.status, result.error
    File.read(output)
  end

end
