# frozen_string_literal: true

require "test_helper"

# Vectors in a dense_vector field: written by the writer, found with a knn query, read back.
class VectorsTest < Minitest::Test

  include Integration

  MAPPINGS = {properties: {title: {type: "keyword"},
                           embedding: {type: "dense_vector", dims: 3, similarity: "cosine"}}}.freeze
  BOOKS = [{"id" => "1", "title" => "Moby-Dick", "embedding" => [1.0, 0.0, 0.0]},
           {"id" => "2", "title" => "Billy Budd", "embedding" => [0.9, 0.1, 0.0]},
           {"id" => "3", "title" => "Walden", "embedding" => [0.0, 0.0, 1.0]}].freeze

  def setup
    super
    create_index(mappings: MAPPINGS)
    writer = Metacrunch::Elasticsearch::Writer.new(connection, index: @index, id: "id")
    writer.open(context)
    writer.write_batch(BOOKS)
    client.indices.refresh(index: @index)
  end

  def test_writes_and_finds_vectors
    search = Metacrunch::Elasticsearch::Search.new(connection, index: @index)
    query = {knn: {field: "embedding", query_vector: [1.0, 0.0, 0.0], k: 2, num_candidates: 10}}

    assert_equal ["1", "2"], search.ids(query, size: 2)
  end

  def test_reads_vectors_back
    records = read(source: vectors_in_answers? ? nil : {exclude_vectors: false})

    assert_equal(["2", "1", "3"], records.map { it["id"] })
    BOOKS.values_at(1, 0, 2).zip(records).each do |book, record|
      book["embedding"].zip(record["embedding"]) { |expected, actual| assert_in_delta expected, actual, 1e-6 }
    end
  end

  def test_from_9_2_answers_leave_vectors_out
    skip "Elasticsearch #{version} keeps vectors in answers" if vectors_in_answers?

    refute(read.any? { it.key?("embedding") })
  end

  private

  def read(**)
    reader = Metacrunch::Elasticsearch::Reader.new(connection, index: @index, sort: [{title: "asc"}], **)
    reader.open(context)
    reader.each.to_a
  end

  def version = client.info.body.dig("version", "number")

  # Before 9.2, Elasticsearch gives vectors in _source like any other field.
  def vectors_in_answers? = Gem::Version.new(version) < Gem::Version.new("9.2")

end
