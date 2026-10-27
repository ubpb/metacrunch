# frozen_string_literal: true

require "test_helper"

class ReaderTest < Minitest::Test

  include Pages

  Reader = Metacrunch::Elasticsearch::Reader
  NOT_FOUND = {"error" => {"type" => "index_not_found_exception", "reason" => "no such index [books]"}}.freeze

  def setup
    @fake = FakeElasticsearch.new
    @log = StringIO.new
  end

  def test_reads_the_documents_page_by_page
    serve_pages(@fake, documents(5))

    assert_equal([1, 2, 3, 4, 5], open_reader(size: 2).each.map { it["n"] })
    assert_equal([nil, [2], [4]], searches.map { it["search_after"] })
  end

  def test_each_page_uses_the_newest_point_in_time_which_is_closed_at_the_end
    serve_pages(@fake, documents(3))
    open_reader(size: 2).each.to_a

    assert_equal(["pit-0", "pit-2"], searches.map { it.dig("pit", "id") })
    assert_equal [{"id" => "pit-3"}], closes
  end

  def test_a_full_last_page_needs_one_more_search
    serve_pages(@fake, documents(4))

    assert_equal 4, open_reader(size: 2).each.count
    assert_equal 3, searches.size
  end

  def test_asks_for_the_query_source_and_sort_and_counts_hits_on_the_first_page_only
    serve_pages(@fake, documents(3))
    open_reader(query: {term: {lang: "en"}}, source: ["n"], sort: [{n: "desc"}], size: 2, keep_alive: "1m").each.to_a
    first, second = searches

    assert_equal [{"term" => {"lang" => "en"}}, ["n"], [{"n" => "desc"}], "1m"],
                 [first["query"], first["_source"], first["sort"], first.dig("pit", "keep_alive")]
    assert_equal [true, false], [first["track_total_hits"], second["track_total_hits"]]
  end

  def test_by_default_all_documents_in_shard_order
    serve_pages(@fake, documents(1))
    open_reader.each.to_a
    search = searches.first

    assert_equal [[{"_shard_doc" => "asc"}], 1000], search.values_at("sort", "size")
    refute search.key?("query")
  end

  def test_hits_keep_index_and_id_without_sort_and_score
    serve_pages(@fake, documents(1))

    assert_equal [{"_index" => "books", "_id" => "1", "_source" => {"n" => 1}}], open_reader(hits: true).each.to_a
  end

  def test_progress_follows_the_hits_read
    serve_pages(@fake, documents(4))
    reader = open_reader(size: 2)
    before = reader.progress
    seen = reader.each.map { reader.progress }

    assert_nil before
    assert_equal [0.25, 0.5, 0.75, 1.0], seen
  end

  def test_progress_of_an_empty_result_is_complete
    serve_pages(@fake, [])
    reader = open_reader

    assert_empty reader.each.to_a
    assert_in_delta 1.0, reader.progress
  end

  def test_leaving_early_closes_the_point_in_time
    serve_pages(@fake, documents(5))
    reader = open_reader(size: 2)
    reader.each { break }
    assert_raises(RuntimeError) { reader.each { raise "step failed" } }

    assert_equal 2, closes.size
  end

  def test_a_second_each_reads_again
    serve_pages(@fake, documents(2))
    reader = open_reader

    assert_equal [2, 2], [reader.each.count, reader.each.count]
  end

  def test_each_connects_without_open
    serve_pages(@fake, documents(2))

    assert_equal 2, Reader.new(@fake.connection, index: "books").each.count
  end

  def test_searches_refuse_partial_results
    serve_pages(@fake, documents(3))
    open_reader(size: 2).each.to_a
    params = @fake.calls.select { it.path == "/_search" }.map { it.params["allow_partial_search_results"] }

    assert_equal ["false", "false"], params
  end

  def test_a_read_that_ends_short_of_the_total_is_an_input_error
    serve_pages(@fake, documents(3))
    @fake.on("POST", "/_search") do |request|
      start = request.json["search_after"]&.first || 0
      hits = documents(3)[start, 2].each_with_index.map { |hit, offset| hit.merge("sort" => [start + offset + 1]) }
      [200, {"pit_id" => "pit-1", "hits" => {"total" => {"value" => 6, "relation" => "eq"}, "hits" => hits}}]
    end
    error = assert_raises(Metacrunch::InputError) { open_reader(size: 2).each.to_a }

    assert_equal "elasticsearch books: got 3 of 6 documents; shards failed while reading", error.message
  end

  def test_a_pattern_without_indices_gives_no_records
    serve_pages(@fake, [], index: "books-*")

    assert_empty Reader.new(@fake.connection, index: "books-*").each.to_a
  end

  def test_an_expired_point_in_time_asks_for_a_longer_keep_alive
    serve_pages(@fake, documents(3))
    first_page = {"pit_id" => "pit-2", "hits" => {"hits" => documents(2).map { it.merge("sort" => [1]) }}}
    # As Elasticsearch 8 and 9 answer: the cause is in root_cause.
    expired = {"error" => {"root_cause" => [{"type" => "search_context_missing_exception",
                                             "reason" => "No search context found for id [7]"}],
                           "type" => "search_phase_execution_exception", "reason" => "all shards failed"}}
    @fake.on("POST", "/_search") { |request| request.json["search_after"] ? [404, expired] : [200, first_page] }
    error = assert_raises(Metacrunch::InputError) { open_reader(size: 2).each.to_a }

    assert_equal "elasticsearch books: 404 search_phase_execution_exception: all shards failed; " \
                 "the point in time expired between two pages: give the reader a longer keep_alive", error.message
  end

  def test_a_missing_index_is_an_input_error
    @fake.on("POST", "/books/_pit") { [404, NOT_FOUND] }
    error = assert_raises(Metacrunch::InputError) { open_reader.each.to_a }

    assert_equal "elasticsearch books: 404 index_not_found_exception: no such index [books]", error.message
  end

  def test_a_failed_connection_is_an_input_error
    @fake.on("GET", "/") { raise Faraday::ConnectionFailed, "Connection refused" }
    reader = Reader.new(@fake.connection(retries: 0), index: ["books", "papers"])
    error = assert_raises(Metacrunch::InputError) { reader.open(context) }

    assert_equal "elasticsearch books,papers: request to #{FakeElasticsearch::URL} failed: Connection refused",
                 error.message
  end

  def test_a_failed_close_is_only_logged
    serve_pages(@fake, documents(1))
    @fake.on("DELETE", "/_pit") { [500, {"error" => {"type" => "x", "reason" => "y"}}] }

    assert_equal 1, open_reader.each.count
    assert_match "WARN -- : elasticsearch books: could not close the point in time: 500 x: y", @log.string
  end

  def test_inspect_shows_no_credentials
    serve_pages(@fake, documents(1))
    reader = Reader.new(@fake.connection(api_key: "k3y"), index: "books").tap { it.open(context) }

    assert_equal "#<Metacrunch::Elasticsearch::Reader index=books connection=#<Metacrunch::Elasticsearch::Connection " \
                 "url=#{FakeElasticsearch::URL} api_key=[FILTERED]>>", reader.inspect
  end

  def test_validates_its_options
    {
      {index: ""} => 'index must be a name, alias or pattern, or an Array of them, got ""',
      {query: "title:x"} => "query must be a Hash, got String",
      {source: false} => "source: false needs hits: true",
      {source: 1} => "source must be true, false, a field, an Array of fields or a Hash, got Integer",
      {sort: 1} => "sort must be a field, an Array or a Hash, got Integer",
      {size: 10_001} => "size must be an Integer from 1 to 10000, got 10001",
      {keep_alive: 5} => 'keep_alive must be an Elasticsearch time value such as "5m", got 5'
    }.each do |options, message|
      error = assert_raises(ArgumentError) { Reader.new(@fake.connection, index: "books", **options) }

      assert_equal message, error.message
    end
  end

  private

  def context = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(@log))

  def open_reader(**)
    Reader.new(@fake.connection, index: "books", **).tap { it.open(context) }
  end

  def searches = @fake.calls.select { it.path == "/_search" }.map(&:json)

  def closes = @fake.calls.select { it.verb == "DELETE" }.map(&:json)

end
