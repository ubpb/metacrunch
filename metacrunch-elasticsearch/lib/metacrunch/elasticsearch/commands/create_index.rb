# frozen_string_literal: true

Metacrunch.command "es:create-index", desc: "Create an Elasticsearch index, by name or for an alias" do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :alias, String, desc: "name the index ALIAS-YYYYMMDD-HHMMSS (UTC) instead of NAME"
    param :settings, String, desc: "JSON file with the settings (comments allowed)"
    param :mappings, String, desc: "JSON file with the mappings (comments allowed)"
    param :bulk_load, :bool, desc: "no refresh and no replicas until es:finish-load"
    param :skip_existing, :bool, desc: "warn instead of failing when NAME exists"
    args :name, max: 1, desc: "NAME"
  end

  run do
    name = params.name.first
    raise Metacrunch::ParamError, "es:create-index needs NAME or --alias, not both" if name.nil? == params.alias.nil?
    raise Metacrunch::ParamError, "--skip-existing works with NAME only" if params.skip_existing && params.alias

    indices = Metacrunch::Elasticsearch::Indices.new(Metacrunch::Elasticsearch::Connection.from_params(params), logger:)
    definition = {settings: params.settings, mappings: params.mappings, bulk_load: params.bulk_load}
    next indices.create_for(params.alias, **definition) if params.alias

    if params.skip_existing && indices.exists?(name)
      logger.warn("#{name} exists, skipped")
      next name
    end
    indices.create(name, **definition)
  end
end
