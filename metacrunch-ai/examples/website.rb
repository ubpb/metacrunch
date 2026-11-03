# frozen_string_literal: true

# Reads the pages of a website from its sitemaps, fetches them politely, extracts their text, cuts it into chunks,
# adds a vector to every chunk and writes the chunks as JSON Lines, without crawling:
#
#   bundle exec metacrunch run examples/website.rb --site https://www.example.org --tika-url http://localhost:9997 \
#     --embeddings-url http://localhost:11435/v1 --embeddings-model all-minilm --output tmp/chunks.jsonl
#
# The test site of this gem stands in for a real one: start it with `docker compose -f test/compose.yml up -d --wait`
# and pass --site http://127.0.0.1:8089. With --embeddings-url fake:384 it embeds without a service.
require "metacrunch/ai"

Metacrunch.job do
  params do
    param :site, String, required: true, desc: "the website, e.g. https://www.example.org"
    param :delay, Float, default: 1.0, desc: "seconds between two requests to the site"
    param :output, String, required: true, desc: "JSON Lines file to write"
    use Metacrunch::Ai::TIKA_PARAMS
    use Metacrunch::Ai::EMBEDDINGS_PARAMS
  end

  source Metacrunch::Ai::Sitemap::Reader.site(params.site, delay: params.delay), id: ->(page) { page["id"] }
  map Metacrunch::Ai::Fetch.new(delay: params.delay)
  map Metacrunch::Ai::Extract.new(Metacrunch::Ai::Html.new(content: "main"), Metacrunch::Ai::Text.new,
                                  Metacrunch::Ai.tika(params))
  flat_map Metacrunch::Ai::Chunk.new(size: 600, overlap: 100)
  map Metacrunch::Ai::Embed.new(Metacrunch::Ai.embedder(params), text: ["title", "headings", "text"]), batch: 32
  sink Metacrunch::JsonLines::Writer.new(params.output)
  on_failure :skip
end
