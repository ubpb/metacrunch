# frozen_string_literal: true

# Answers bulk requests of a FakeElasticsearch item by item: the block gets
# action and id of each item and returns its status (200 by default); 400 and
# above come with an error. Records the actions of every request.
module BulkAnswers

  ERRORS = {
    400 => {"type" => "document_parsing_exception", "reason" => "failed to parse field [year]"},
    404 => {"type" => "document_missing_exception", "reason" => "document missing"},
    409 => {"type" => "version_conflict_engine_exception", "reason" => "document already exists"},
    429 => {"type" => "es_rejected_execution_exception", "reason" => "rejected execution"},
    503 => {"type" => "unavailable_shards_exception", "reason" => "primary shard is not active"}
  }.freeze

  # The writer's checks at open find books open and without blocks.
  def serve_bulk(fake, &status)
    fake.on("HEAD", "/books") { [200, nil] }
    fake.on("GET", "/_alias/books") { [404, {"error" => "alias [books] missing", "status" => 404}] }
    fake.on("GET", %r{\A/_cat/indices/}) do |request|
      [200, request.path.split("/").last.split(",").map { {"index" => it, "status" => "open"} }]
    end
    fake.on("GET", %r{\A/[^_][^/]*/_settings\z}) { [200, {}] }
    fake.on("POST", "/_bulk") do |request|
      items = bulk_actions(request).map do |action, target|
        code = status&.call(action, target["_id"]) || 200
        result = {"status" => code}
        result["error"] = ERRORS.fetch(code) if code >= 400
        {action => result}
      end
      [200, {"errors" => items.any? { it.values.first["status"] >= 300 }, "items" => items}]
    end
  end

  # The [action, target] pairs of a bulk request.
  def bulk_actions(request)
    request.ndjson.filter_map do |line|
      line.first if line.size == 1 && ["index", "create", "update", "delete"].include?(line.keys.first)
    end
  end

  # The ids of each bulk request sent so far.
  def bulk_ids(fake)
    fake.calls.select { it.path == "/_bulk" }.map { |request| bulk_actions(request).map { it.last["_id"] } }
  end

end
