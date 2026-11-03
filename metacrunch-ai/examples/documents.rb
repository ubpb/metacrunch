# frozen_string_literal: true

# Reads the documents of directories (HTML, Markdown, PDF, Word), extracts their text, cuts it into chunks, adds a
# vector to every chunk and writes the chunks as JSON Lines, ready for a vector index:
#
#   docker compose -f test/compose.yml up -d --wait
#   bundle exec metacrunch run examples/documents.rb --tika-url http://localhost:9997 \
#     --embeddings-url http://localhost:11435/v1 --embeddings-model all-minilm \
#     --output tmp/chunks.jsonl examples/data/documents
#
# With --embeddings-url fake:384 it embeds without a service; PDF and Word files need Tika.
require "metacrunch/ai"

Metacrunch.job do
  params do
    use Metacrunch::Ai::TIKA_PARAMS
    use Metacrunch::Ai::EMBEDDINGS_PARAMS
    param :output, String, required: true, desc: "JSON Lines file to write"
    args :directories, min: 1, desc: "directories with documents"
  end

  source Metacrunch::FileList::Reader.new(params.directories), id: ->(file) { file["id"] }
  map Metacrunch::Ai::Extract.new(Metacrunch::Ai::Html.new(content: "main"), Metacrunch::Ai::Text.new,
                                  Metacrunch::Ai.tika(params))
  flat_map Metacrunch::Ai::Chunk.new(size: 600, overlap: 100)
  map Metacrunch::Ai::Embed.new(Metacrunch::Ai.embedder(params), text: ["title", "headings", "text"]), batch: 32
  sink Metacrunch::JsonLines::Writer.new(params.output)
end
