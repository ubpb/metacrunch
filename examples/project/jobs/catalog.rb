# frozen_string_literal: true

# Writes the public titles of a JSON Lines file to DIR/titles.jsonl. A
# record without a title fails; on_error :skip lets the run go on, and it
# ends with failed records (exit status 3).
#
#   cd examples/project
#   bundle exec metacrunch catalog --help
#   mkdir -p ../../tmp && bundle exec metacrunch catalog --output ../../tmp
Metacrunch.job "catalog", desc: "Write the public titles into a directory" do
  params do
    param :output, String, required: true, desc: "Directory for titles.jsonl; must exist"
    param :input, String, default: File.expand_path("../data/titles.jsonl", __dir__),
                          desc: "JSON Lines with title records"
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  reject("Not public") { !it["public"] }
  map { |record| {"id" => record["id"], "title" => record.fetch("title")} }
  sink Metacrunch::JsonLines::Writer.new(File.join(params.output, "titles.jsonl"))
  on_error :skip
end
