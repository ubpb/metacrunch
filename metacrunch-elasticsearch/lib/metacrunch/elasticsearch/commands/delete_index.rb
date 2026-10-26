# frozen_string_literal: true

Metacrunch.command "es:delete-index", desc: "Delete an Elasticsearch index that no alias points to" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :force, :bool, desc: "delete it even if an alias points to it"
    args :name, min: 1, max: 1, desc: "NAME"
  end

  run do
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.delete(params.name.first, force: params.force)
  end
end
