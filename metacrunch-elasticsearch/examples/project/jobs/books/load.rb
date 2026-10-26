# frozen_string_literal: true

Metacrunch.job "books:load", desc: "Load books from JSON Lines into an index or alias" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :index, String, required: true, desc: "index or alias to write to"
    param :input, String, desc: "JSON Lines with books (default: data/books.jsonl)"
  end

  es = Metacrunch::Elasticsearch::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.input || root.join("data/books.jsonl").to_s)
  map { it.merge("title" => it["title"].strip) }
  # A book marked "deleted" is removed from the index; the others are indexed (or replaced).
  sink Metacrunch::Elasticsearch::Writer.new(es, index: params.index, id: "isbn",
                                                 action: ->(book) { book["deleted"] ? :delete : :index }),
       batch: 1000
end
