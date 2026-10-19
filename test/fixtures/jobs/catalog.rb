# frozen_string_literal: true

require_relative "lib/json_files"

# Example job that uses the whole DSL.
Metacrunch.job "catalog" do
  params do
    param :output, String, required: true, desc: "Directory for the output files"
    param :min_year, Integer, default: 1900, env: "CATALOG_MIN_YEAR", desc: "Oldest year to keep"
    args :input, min: 1, max: 1, desc: "JSON file with an array of records"
  end

  source JsonArrayFile.new(params.input.first), id: ->(record) { record["_id"] }

  reject("Not public") { !it["public"] }
  filter { it["year"].nil? || it["year"] >= params.min_year }
  map do |record, ctx|
    ctx.mark("No title") if record["title"].nil?
    {"id" => record["_id"], "title" => record["title"], "year" => record["year"], "isbns" => record.fetch("isbns")}
  end
  flat_map do |record|
    isbns = record.delete("isbns")
    isbns.empty? ? [record] : isbns.map { |isbn| record.merge("isbn" => isbn) }
  end

  sink JsonLinesFile.new(File.join(params.output, "records.jsonl")), batch: 2
  rejects JsonLinesFile.new(File.join(params.output, "rejects.jsonl"))
  failures JsonLinesFile.new(File.join(params.output, "failures.jsonl"))
  on_failure :skip, max_failures: 5

  after { |result| logger.info("catalog finished: #{result.status}") }
end
