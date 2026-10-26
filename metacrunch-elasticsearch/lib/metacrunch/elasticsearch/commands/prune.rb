# frozen_string_literal: true

Metacrunch.command "es:prune", desc: "Delete the indices of an alias older than the one it points to" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :keep, Integer, default: 1, desc: "how many of the older indices to keep"
    param :dry_run, :bool, desc: "only log what would be deleted"
    args :alias, min: 1, max: 1, desc: "ALIAS"
  end

  run do
    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    indices.prune(params.alias.first, keep: params.keep, dry_run: params.dry_run)
  end
end
