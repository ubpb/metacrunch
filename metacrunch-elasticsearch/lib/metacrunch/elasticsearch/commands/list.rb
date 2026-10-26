# frozen_string_literal: true

Metacrunch.command "es:list", desc: "List Elasticsearch indices with their aliases, documents, size and health" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    args :pattern, max: 1, desc: "PATTERN (default: all)"
  end

  run do
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.list(params.pattern.first || "*").tap { puts Metacrunch::Elasticsearch::Indices.table(it) }
  end
end
