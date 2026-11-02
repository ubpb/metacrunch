# frozen_string_literal: true

require "metacrunch/ai"

Metacrunch.job "embed", desc: "Add the vectors of the titles" do
  params { use Metacrunch::Ai::EMBEDDINGS_PARAMS }

  map Metacrunch::Ai::Embed.new(Metacrunch::Ai.embedder(params), text: "title"), batch: 4
end
