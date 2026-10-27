# frozen_string_literal: true

Metacrunch.command "es:switch-alias", desc: "Point an Elasticsearch alias to an index, atomically" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    args :names, min: 2, max: 2, desc: "ALIAS INDEX"
  end

  run do
    alias_name, index = params.names
    Metacrunch::Elasticsearch::Names.check(alias_name, "alias", error: Metacrunch::ParamError)
    Metacrunch::Elasticsearch::Names.check(index, "index", error: Metacrunch::ParamError)
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.switch_alias(alias_name, index)
  end
end
