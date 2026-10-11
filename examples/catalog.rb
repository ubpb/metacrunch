# frozen_string_literal: true

require_relative "lib/json_array_file"

# A catalog export: reads a JSON array of title records, drops what must not
# be published, writes one record per ISBN as JSON Lines. Shows the whole
# DSL: parameters, reject with a reason, filter, marks, flat_map, the
# rejects and errors sinks, the error policy and an after hook.
#
#   mkdir -p tmp
#   bundle exec metacrunch run examples/catalog.rb --output tmp examples/data/catalog.json
#   bundle exec metacrunch trace -n 3 examples/catalog.rb --output tmp examples/data/catalog.json
#   bundle exec metacrunch run examples/catalog.rb --help
#
# examples/data/catalog.json gives 7 records, 2 rejects (not public) and 1
# error (a year that is not a number); the exit status is 3, "finished, but
# records failed".
Metacrunch.job "catalog" do
  params do
    param :output, String, required: true, desc: "Directory for records.jsonl, rejects.jsonl and errors.jsonl"
    param :min_year, Integer, default: 1900, env: "CATALOG_MIN_YEAR", desc: "Oldest year to keep"
    args :input, min: 1, max: 1, desc: "JSON file with an array of records"
  end

  source Examples::JsonArrayFile.new(params.input.first), id: ->(record) { record["_id"] }

  reject("Not public") { !it["public"] }
  filter(name: "recent") { it["year"] >= params.min_year }
  map(name: "shape") do |record, ctx|
    ctx.mark("No title") if record["title"].nil?
    {"id" => record["_id"], "title" => record["title"], "year" => record["year"], "isbns" => record.fetch("isbns", [])}
  end
  flat_map(name: "per_isbn") do |record|
    isbns = record.delete("isbns")
    isbns.empty? ? [record] : isbns.map { |isbn| record.merge("isbn" => isbn) }
  end

  sink Metacrunch::JsonLines::Writer.new(File.join(params.output, "records.jsonl")), batch: 100
  rejects Metacrunch::JsonLines::ContextWriter.new(File.join(params.output, "rejects.jsonl"))
  errors Metacrunch::JsonLines::ContextWriter.new(File.join(params.output, "errors.jsonl"))
  on_error :skip, max_errors: 10

  after { |result| logger.info("catalog: #{result.stats.written} records in #{params.output}") }
end
