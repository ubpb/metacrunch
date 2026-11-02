# frozen_string_literal: true

# Adds a vector of title, abstract and subjects to books read from JSON Lines, and writes them as JSON Lines. A book
# without any of them passes without a vector, with the mark "No text to embed":
#
#   bundle exec metacrunch run examples/embed.rb --embeddings-url http://localhost:11435/v1 \
#     --embeddings-model all-minilm --output tmp/books.jsonl examples/data/books.jsonl
#
# With --embeddings-url fake:384 it runs without a service, with fake vectors of 384 dimensions.
require "metacrunch/ai"

Metacrunch.job do
  params do
    use Metacrunch::Ai::EMBEDDINGS_PARAMS
    param :output, String, required: true, desc: "JSON Lines file to write"
    args :files, min: 1, desc: "JSON Lines files with books"
  end

  embedder = Metacrunch::Ai.embedder(params)
  source Metacrunch::JsonLines::Reader.new(params.files), id: ->(book) { book["isbn"] }
  map Metacrunch::Ai::Embed.new(embedder, text: ["title", "abstract", "subjects"]), batch: 32
  sink Metacrunch::JsonLines::Writer.new(params.output)
end
