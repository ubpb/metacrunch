# frozen_string_literal: true

Metacrunch.job "books:load", desc: "Load books from JSON Lines into the table books" do
  params do
    instance_exec(&Metacrunch::Db::CONNECTION_PARAMS)
    param :input, String, desc: "JSON Lines with books (default: data/books.jsonl)"
    param :failures, String, default: "failures.jsonl", desc: "JSON Lines for the books the database refuses"
  end

  db = Metacrunch::Db::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.input || root.join("data/books.jsonl").to_s),
         id: ->(book) { book["isbn"] }
  # A book marked "deleted" is removed (the flag is no column, and a delete uses only the key); the others are added
  # or updated. The date as ISO 8601 text, which the date column takes, keeps the record JSON for the failures file.
  map do |book|
    next book if book["deleted"]

    book.slice("isbn", "title", "author", "year").merge("added_on" => Date.today.iso8601)
  end
  sink Metacrunch::Db::Writer.new(db, table: "books", key: "isbn",
                                      action: ->(book) { book["deleted"] ? :delete : :upsert }),
       batch: 1000
  failures Metacrunch::JsonLines::ContextWriter.new(params.failures)
  on_failure :skip, max_failures: 100
end
