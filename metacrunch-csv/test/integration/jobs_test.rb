# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class JobsTest < Minitest::Test

  Csv = Metacrunch::Csv

  def setup
    @dir = Dir.mktmpdir
    @input = File.join(@dir, "in.csv")
    File.write(@input, "id,title,year\n1,Moby,1851\n2,\"Emma\",1815\n3,\"bad\"quote,1900\n")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_csv_to_csv_with_and_without_workers
    outputs = [nil, 2].map do |workers|
      output = File.join(@dir, "out-#{workers}.csv")
      result = copy_job(output).run(workers:, logger: Logger.new(nil))

      assert_equal :ok_with_failures, result.status
      File.read(output)
    end

    assert_equal ["year,title\n1851,MOBY\n1815,EMMA\n"], outputs.uniq
  end

  def test_an_unreadable_row_fails_alone
    input = @input
    job = Metacrunch.job do
      source Csv::Reader.new(input)
      on_failure :skip
    end
    result = Metacrunch::Testing.run(job)

    assert_equal 2, result.records.size
    assert_equal(["source"], result.failures.map { it.last.step })
    assert_instance_of CSV::MalformedCSVError, result.failures.first.last.error
  end

  def test_a_value_the_writer_refuses_aborts_the_run
    output = File.join(@dir, "out.csv")
    input = @input
    job = Metacrunch.job do
      source Csv::Reader.new(input)
      on_failure :skip
      map { it["id"] == "2" ? it.merge("year" => Time.now) : it }
      sink Csv::Writer.new(output)
    end
    result = job.run(logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_equal "id,title,year\n1,Moby,1851\n", File.read(output)
  end

  # The engine does not close a sink whose open raised; the writer closes
  # its output itself, so the gzip file is complete.
  def test_a_header_that_fails_in_open_still_finishes_the_file
    output = File.join(@dir, "out.csv.gz")
    input = @input
    job = Metacrunch.job do
      source Csv::Reader.new(input)
      sink Csv::Writer.new(output, columns: ["€"], encoding: "ISO-8859-1")
    end

    assert_equal :aborted, job.run(logger: Logger.new(nil)).status
    assert_empty Zlib.gunzip(File.binread(output))
  end

  private

  def copy_job(output)
    input = @input
    Metacrunch.job do
      source Csv::Reader.new(input)
      on_failure :skip
      map { it.merge("title" => it["title"].upcase) }
      sink Csv::Writer.new(output, columns: ["year", "title"])
    end
  end

end
