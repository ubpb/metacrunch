# frozen_string_literal: true

# Prints the ids of the public titles as JSON Lines: the transform of the
# job catalog, with another value for its parameter fields.
#
#   cd examples/project
#   bundle exec metacrunch catalog:ids
Metacrunch.job "catalog:ids", desc: "Print the ids of the public titles" do
  params do
    param :input, String, default: File.expand_path("../../data/titles.jsonl", __dir__),
                          desc: "JSON Lines with title records"
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  use "catalog:public", fields: ["id"]
end
