# frozen_string_literal: true

# Loads books from JSON Lines into an Elasticsearch index, with the ISBN as _id. Books the index refuses (here a year
# that is no number) go to failures.jsonl, and the run ends with exit status 3:
#
#   bundle exec metacrunch run --params examples/params.yml examples/load.rb --index books examples/data/books.jsonl
#
# examples/params.yml connects to Elasticsearch. The index must exist; examples/project creates one behind the alias
# books (bundle exec metacrunch run --params params.yml books:rebuild there).
require "metacrunch/elasticsearch"

Metacrunch.job do
  params do
    use Metacrunch::Elasticsearch::CONNECTION_PARAMS
    param :index, String, required: true, desc: "index or alias to write to"
    param :failures, String, default: "failures.jsonl", desc: "where the refused books go"
    args :files, min: 1, desc: "JSON Lines files with books"
  end

  es = Metacrunch::Elasticsearch::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.files)
  sink Metacrunch::Elasticsearch::Writer.new(es, index: params.index, id: "isbn"), batch: 1000
  failures Metacrunch::JsonLines::ContextWriter.new(params.failures)
  on_failure :skip
end
