# frozen_string_literal: true

Metacrunch.command "es:finish-load", desc: "Restore refresh interval and replicas of an index after a bulk load" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :settings, String, desc: "JSON file with the settings to restore (default: Elasticsearch's)"
    args :index, min: 1, max: 1, desc: "INDEX"
  end

  run do
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.finish_load(params.index.first, settings: params.settings)
  end
end
