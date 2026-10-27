# frozen_string_literal: true

# Serves documents from a FakeElasticsearch as Elasticsearch does for a
# point in time: POST /INDEX/_pit opens one, POST /_search pages through the
# documents by search_after, each answer with a new point-in-time id, and
# DELETE /_pit closes it.
module Pages

  # A document as a hit: _id "1", "2", ... and _source {"n" => 1}, ...
  def documents(count) = (1..count).map { {"_index" => "books", "_id" => it.to_s, "_source" => {"n" => it}} }

  def serve_pages(fake, documents, index: "books")
    fake.on("POST", "/#{index}/_pit") { [200, {"id" => "pit-0"}] }
    fake.on("DELETE", "/_pit") { [200, {"succeeded" => true}] }
    fake.on("POST", "/_search") do |request|
      body = request.json
      start = body["search_after"]&.first || 0
      hits = documents[start, body["size"]].each_with_index.map do |hit, offset|
        hit.merge("sort" => [start + offset + 1], "_score" => nil)
      end
      answer = {"pit_id" => "pit-#{start + hits.size}", "hits" => {"hits" => hits}}
      answer["hits"]["total"] = {"value" => documents.size, "relation" => "eq"} if body["track_total_hits"]
      [200, answer]
    end
  end

end
