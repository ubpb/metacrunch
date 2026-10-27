# frozen_string_literal: true

require "securerandom"

# For the tests in test/integration: they run against the Elasticsearch at
# ELASTICSEARCH_URL as ELASTICSEARCH_USER with ELASTICSEARCH_PASSWORD (see
# test/compose.yml) and skip without ELASTICSEARCH_URL. Each test gets a name
# of its own (@index); the indices whose names start with it are deleted
# afterwards, with their aliases.
module Integration

  def setup
    skip "needs Elasticsearch: set ELASTICSEARCH_URL (see test/compose.yml)" unless ENV["ELASTICSEARCH_URL"]

    @index = "metacrunch-test-#{SecureRandom.hex(4)}"
    super
  end

  def teardown
    if @index
      names = client.cat.indices(index: "#{@index}*", format: "json", h: "index", expand_wildcards: "all").body
      names.each { client.indices.delete(index: it["index"]) }
    end
    super
  end

  def connection(**)
    Metacrunch::Elasticsearch::Connection.new(url: ENV.fetch("ELASTICSEARCH_URL"),
                                              user: ENV.fetch("ELASTICSEARCH_USER", "elastic"),
                                              password: ENV.fetch("ELASTICSEARCH_PASSWORD"), **)
  end

  def client = @client ||= connection.connect

  def create_index(name = @index, mappings: {properties: {year: {type: "integer"}}})
    client.indices.create(index: name, body: {mappings:})
    name
  end

  # Indexes documents ({"id" => ...}) and makes them searchable.
  def index_documents(documents, index: @index)
    body = documents.flat_map { [{index: {_index: index, _id: it["id"]}}, it] }
    client.bulk(body:, refresh: true)
  end

  # The documents of index by _id, after a refresh.
  def stored(index = @index)
    client.indices.refresh(index:)
    hits = client.search(index:, body: {size: 1000, query: {match_all: {}}}).body.dig("hits", "hits")
    hits.to_h { [it["_id"], it["_source"]] }
  end

  # The search contexts open on the cluster; a point in time keeps one per shard.
  def open_points_in_time
    nodes = client.nodes.stats(metric: "indices", index_metric: "search").body["nodes"]
    nodes.values.sum { it.dig("indices", "search", "open_contexts") }
  end

  def context(log = StringIO.new) = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log))

end
