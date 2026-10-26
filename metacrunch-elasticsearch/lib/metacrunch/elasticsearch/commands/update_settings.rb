# frozen_string_literal: true

Metacrunch.command "es:update-settings", desc: "Change the settings of an Elasticsearch index" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :settings, String, required: true, desc: "JSON file with the settings (number_of_shards is left out)"
    param :reopen, :bool, desc: "close the index first and open it again, e.g. for analyzers"
    args :index, min: 1, max: 1, desc: "INDEX"
  end

  run do
    index = Metacrunch::Elasticsearch::Names.check(params.index.first, "index", error: Metacrunch::ParamError)
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.update_settings(index, params.settings, reopen: params.reopen)
  end
end
