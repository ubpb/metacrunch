# frozen_string_literal: true

Metacrunch.command "books:rebuild", desc: "Load the books into a new index and switch the alias to it" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :alias, String, default: "books", desc: "the alias to switch"
    param :input, String, desc: "JSON Lines with books (default: data/books.jsonl)"
  end

  run do
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    settings = root.join("config/books.settings.jsonc")
    mappings = root.join("config/books.mappings.jsonc")
    index = indices.create_for(params.alias, settings:, mappings:, bulk_load: true)
    switched = false
    begin
      result = invoke "books:load", params: {**params.to_h.except(:alias), index:}
      # A load that refused books leaves the alias where it is.
      next logger.warn("books:rebuild: #{result.status}; #{params.alias} not switched") unless result.ok?

      indices.finish_load(index, settings:)
      indices.switch_alias(params.alias, index)
      switched = true
    ensure
      # Also after an abort: prune would otherwise keep a half-loaded index as the one to go back to.
      indices.delete(index) unless switched
    end
    indices.prune(params.alias, keep: 1)
    index
  end
end
