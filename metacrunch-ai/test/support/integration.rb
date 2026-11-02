# frozen_string_literal: true

# For the tests in test/integration: they run against the embeddings server at EMBEDDINGS_URL with the model
# EMBEDDINGS_MODEL (all-minilm by default; see test/compose.yml) and skip without EMBEDDINGS_URL.
module Integration

  HINT = "needs an embeddings server: set EMBEDDINGS_URL (see test/compose.yml)"
  BIN = Gem.loaded_specs.fetch("metacrunch").bin_file("metacrunch")

  def setup
    skip HINT unless ENV["EMBEDDINGS_URL"]

    super
  end

  def url = ENV.fetch("EMBEDDINGS_URL")

  def model = ENV.fetch("EMBEDDINGS_MODEL", "all-minilm")

end
