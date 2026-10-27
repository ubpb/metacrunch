# frozen_string_literal: true

require "test_helper"

class ReadingTest < Minitest::Test

  include Integration

  Reader = Metacrunch::Elasticsearch::Reader

  def setup
    super
    create_index
    index_documents((1..25).map { {"id" => it.to_s, "year" => 1900 + it, "lang" => it.odd? ? "en" : "de"} })
  end

  def test_reads_every_document_over_several_pages
    reader = open_reader(size: 10)

    assert_equal (1901..1925).to_a, reader.each.map { it["year"] }.sort
    assert_in_delta 1.0, reader.progress
    assert_equal 0, open_points_in_time
  end

  def test_leaving_early_closes_the_point_in_time
    reader = open_reader(size: 10)
    reader.each { break }
    assert_raises(RuntimeError) { reader.each { raise "step failed" } }

    assert_equal 0, open_points_in_time
  end

  def test_query_source_filter_sort_and_hits
    reader = open_reader(query: {term: {lang: "de"}}, source: ["year"], sort: [{year: "desc"}], size: 5, hits: true)
    hits = reader.each.to_a

    assert_equal [12, "24", {"year" => 1924}], [hits.size, hits.first["_id"], hits.first["_source"]]
    assert_equal [@index], hits.map { it["_index"] }.uniq
  end

  def test_an_index_deleted_while_reading_stops_the_run
    other = create_index("#{@index}-other")
    index_documents((1..3).map { {"id" => "o#{it}", "year" => 2000 + it} }, index: other)
    reader = Reader.new(connection, index: [@index, other], size: 10)
    reader.open(context)
    error = assert_raises(Metacrunch::InputError) do
      reader.each.with_index { |_, position| client.indices.delete(index: other) if position.zero? }
    end

    assert_match "elasticsearch #{@index},#{other}: ", error.message
  end

  def test_a_pattern_without_indices_gives_no_records
    reader = Reader.new(connection, index: "#{@index}-none-*")

    assert_empty reader.each.to_a
  end

  def test_a_missing_index_is_an_input_error
    reader = Reader.new(connection, index: "#{@index}-missing")
    reader.open(context)
    error = assert_raises(Metacrunch::InputError) { reader.each.to_a }

    assert_equal "elasticsearch #{@index}-missing: 404 index_not_found_exception: no such index [#{@index}-missing]",
                 error.message
  end

  def test_search_finds_ids_and_hits
    search = Metacrunch::Elasticsearch::Search.new(connection, index: @index)

    sources = search.hits({term: {year: 1908}}).map { it["_source"] }

    assert_equal ["7"], search.ids({term: {year: 1907}})
    assert_equal [{"year" => 1908, "id" => "8", "lang" => "de"}], sources
  end

  private

  def open_reader(**) = Reader.new(connection, index: @index, **).tap { it.open(context) }

end
