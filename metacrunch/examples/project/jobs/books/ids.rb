# frozen_string_literal: true

# Prints the ids of the public titles as JSON Lines: the transform of the
# job books:export, with another value for its parameter fields.
#
#   cd examples/project
#   bundle exec metacrunch run books:ids
Metacrunch.job "books:ids", desc: "Print the ids of the public titles" do
  params do
    param :input, String, default: File.expand_path("../../data/titles.jsonl", __dir__),
                          desc: "JSON Lines with title records"
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  use "books:public", params: {fields: ["id"]}
end
