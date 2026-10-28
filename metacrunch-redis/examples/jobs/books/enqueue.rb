# frozen_string_literal: true

Metacrunch.job "books:enqueue", desc: "Push books from JSON Lines into the queue" do
  params do
    use Metacrunch::Redis::CONNECTION_PARAMS
    param :queue, String, default: "books", desc: "the queue"
    param :input, String, desc: "JSON Lines with books (default: data/books.jsonl)"
  end

  redis = Metacrunch::Redis::Connection.from_params(params)
  source Metacrunch::JsonLines::Reader.new(params.input || root.join("data/books.jsonl").to_s)
  # While the queue holds 10 000 books, or Redis is full, the job waits for its consumers.
  sink Metacrunch::Redis::QueueWriter.new(redis, queue: params.queue, max_length: 10_000), batch: 100
end
