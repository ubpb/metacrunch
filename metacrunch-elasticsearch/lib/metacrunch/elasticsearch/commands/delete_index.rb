# frozen_string_literal: true

Metacrunch.command "es:delete-index", desc: "Delete an Elasticsearch index that no alias points to" do
  params do
    use Metacrunch::Elasticsearch::CONNECTION_PARAMS
    param :force, :bool, desc: "delete it even if an alias points to it"
    args :name, min: 1, max: 1, desc: "NAME"
  end

  run do
    name = Metacrunch::Elasticsearch::Names.check(params.name.first, "index", error: Metacrunch::ParamError)
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.delete(name, force: params.force)
  end
end
