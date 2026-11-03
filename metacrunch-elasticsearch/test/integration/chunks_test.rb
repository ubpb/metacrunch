# frozen_string_literal: true

require "test_helper"

# Chunk records with vectors, as metacrunch-ai's Chunk and Embed make them: written by the writer, found as passages
# with a knn query, one hit per document with collapse.
class ChunksTest < Minitest::Test

  include Integration

  MAPPINGS = {properties: {parent_id: {type: "keyword"}, chunk: {type: "integer"}, headings: {type: "text"},
                           pages: {type: "integer"}, title: {type: "text"}, text: {type: "text"},
                           embedding: {type: "dense_vector", dims: 3, similarity: "cosine"}}}.freeze
  def self.chunk(parent, number, vector, headings: [], pages: nil)
    {"id" => "#{parent}##{number}", "parent_id" => parent, "chunk" => number, "headings" => headings,
     "pages" => pages, "title" => parent, "text" => "Passage #{number} of #{parent}", "embedding" => vector}.compact
  end

  CHUNKS = [
    chunk("loans.html", 1, [1.0, 0.0, 0.0], headings: ["Loans"]),
    chunk("loans.html", 2, [0.9, 0.1, 0.0], headings: ["Loans", "Renewals"]),
    chunk("loans.html", 3, [0.0, 1.0, 0.0], headings: ["Loans", "Fees"]),
    chunk("rules.pdf", 1, [0.8, 0.2, 0.0], pages: [1]),
    chunk("rules.pdf", 2, [0.0, 0.0, 1.0], pages: [2])
  ].freeze

  def setup
    super
    create_index(mappings: MAPPINGS)
    writer = Metacrunch::Elasticsearch::Writer.new(connection, index: @index, id: "id")
    writer.open(context)
    writer.write_batch(CHUNKS)
    client.indices.refresh(index: @index)
  end

  def test_finds_passages
    hits = search(knn(hits: 3))

    assert_equal(["loans.html#1", "loans.html#2", "rules.pdf#1"], hits.map { it["_id"] })
    assert_equal({"parent_id" => "loans.html", "chunk" => 2, "headings" => ["Loans", "Renewals"],
                  "title" => "loans.html", "text" => "Passage 2 of loans.html"}, hits[1]["_source"])
  end

  def test_collapse_gives_the_best_passage_of_each_document
    hits = search(knn(hits: 5), collapse: {field: "parent_id"})

    assert_equal(["loans.html#1", "rules.pdf#1"], hits.map { it["_id"] })
    assert_equal [1], hits.last["_source"]["pages"]
  end

  private

  def knn(hits:) = {field: "embedding", query_vector: [1.0, 0.0, 0.0], k: hits, num_candidates: 20}

  def search(knn, **)
    body = {knn:, _source: ["parent_id", "chunk", "headings", "pages", "title", "text"], size: 10, **}
    client.search(index: @index, body:).body.dig("hits", "hits")
  end

end
