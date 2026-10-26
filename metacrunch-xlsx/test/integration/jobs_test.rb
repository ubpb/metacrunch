# frozen_string_literal: true

require "test_helper"

class JobsTest < Minitest::Test

  include Helpers

  RECORDS = [
    {"id" => "00123", "title" => "Metadata in practice", "year" => 2004, "copies" => 3},
    {"id" => "00124", "title" => "Cataloging, step by step", "year" => 2019, "copies" => nil}
  ].freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_report_with_and_without_workers
    expected = [
      ["Nr.", "Titel", "Jahr"],
      ["00123", "Metadata in practice", 2004],
      ["00124", "Cataloging, step by step", 2019]
    ]

    [nil, 2].each do |workers|
      path = File.join(@dir, "report-#{workers}.xlsx")
      result = report_job(path).run(workers:, logger: Logger.new(nil))

      assert_equal [:ok, expected], [result.status, rows(path)]
    end
  end

  def test_an_aborted_run_leaves_a_file_that_opens
    path = File.join(@dir, "aborted.xlsx")
    job = Metacrunch.job do
      source RECORDS
      map { it["id"] == "00124" ? raise("broken") : it }
      sink Metacrunch::Xlsx::Writer.new(path, columns: ["id", "title"])
    end
    result = job.run(logger: Logger.new(nil))

    assert_equal :aborted, result.status
    assert_equal [["id", "title"], ["00123", "Metadata in practice"]], rows(path)
  end

  # The engine does not close a sink whose open raised; the writer finishes
  # the file itself.
  def test_an_open_that_fails_still_finishes_the_file
    [{columns: ["a\u0001"]}, {columns: ["id"], widths: {"Titel" => 60}}].each_with_index do |options, index|
      path = File.join(@dir, "open-#{index}.xlsx")
      job = Metacrunch.job do
        source RECORDS
        sink Metacrunch::Xlsx::Writer.new(path, **options)
      end

      assert_equal [:aborted, []], [job.run(logger: Logger.new(nil)).status, rows(path)]
    end
  end

  private

  def report_job(path)
    Metacrunch.job do
      source RECORDS
      sink Metacrunch::Xlsx::Writer.new(path, columns: {"Nr." => "id", "Titel" => "title", "Jahr" => "year"},
                                              widths: {"Titel" => 60})
    end
  end

end
