# frozen_string_literal: true

Metacrunch.job "books:cache", desc: "Keep books from JSON Lines under keys for a day" do
  params do
    use Metacrunch::Redis::CONNECTION_PARAMS
    param :prefix, String, default: "book:", desc: "the start of the keys"
    param :input, String, desc: "JSON Lines with books (default: data/books.jsonl)"
  end

  redis = Metacrunch::Redis::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.input || root.join("data/books.jsonl").to_s)
  # A book marked "deleted" is removed from the cache; the others are set, each for a day.
  sink Metacrunch::Redis::KeyWriter.new(redis, key: "#{params.prefix}%{isbn}", expire: 86_400,
                                               action: ->(book) { book["deleted"] ? :delete : :set }),
       batch: 1000
end
