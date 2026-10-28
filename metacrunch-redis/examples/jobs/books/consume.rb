# frozen_string_literal: true

Metacrunch.job "books:consume", desc: "Take books from the queue and write them as JSON Lines" do
  params do
    use Metacrunch::Redis::CONNECTION_PARAMS
    param :queue, String, default: "books", desc: "the queue"
    param :wait, Float, desc: "end after this many seconds without books (default: wait without end)"
    param :output, String, default: "-", desc: "JSON Lines file (default: stdout)"
  end

  redis = Metacrunch::Redis::Connection.from_params(params)
  # Waits for books; a book reaches the output at most a second after it was taken, also with batch:.
  source Metacrunch::Redis::QueueReader.new(redis, queue: params.queue, wait: params.wait || true),
         id: ->(book) { book["isbn"] }
  reject("Deleted") { it["deleted"] }
  map { |book| book.slice("isbn", "title", "author", "year") }
  sink Metacrunch::JsonLines::Writer.new(params.output), batch: 1000
end
