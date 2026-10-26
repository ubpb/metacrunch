# frozen_string_literal: true

require "test_helper"

class SearchTest < Minitest::Test

  Search = Metacrunch::Elasticsearch::Search
  HITS = [{"_index" => "books", "_id" => "7", "_score" => 1.0, "_source" => {"isbn" => "0306406152"}}].freeze

  def setup
    @fake = FakeElasticsearch.new.on("POST", "/books/_search") { [200, {"hits" => {"hits" => HITS}}] }
    @search = Search.new(@fake.connection, index: "books")
  end

  def test_ids_of_the_matching_documents
    assert_equal ["7"], @search.ids({term: {isbn: "0306406152"}}, size: 2)
    assert_equal({"query" => {"term" => {"isbn" => "0306406152"}}, "size" => 2, "_source" => false},
                 @fake.calls.last.json)
  end

  def test_lookups_refuse_partial_results
    @search.ids({match_all: {}})

    assert_equal "false", @fake.calls.last.params["allow_partial_search_results"]
  end

  def test_hits_of_the_matching_documents
    assert_equal [{"_index" => "books", "_id" => "7", "_source" => {"isbn" => "0306406152"}}],
                 @search.hits({match_all: {}})
    assert_equal 10, @fake.calls.last.json["size"]
  end

  def test_one_client_per_process
    2.times { @search.ids({match_all: {}}) }
    reader, writer = IO.pipe
    pid = fork do
      @search.ids({match_all: {}})
      writer.puts(@fake.requests.count { it.path == "/" })
      exit!(0)
    end
    writer.close
    Process.wait(pid)

    assert_equal [1, "2"], [@fake.requests.count { it.path == "/" }, reader.read.strip]
  end

  def test_errors_name_the_index
    @fake.on("POST", "/books/_search") do
      [400, {"error" => {"type" => "parsing_exception", "reason" => "unknown query"}}]
    end
    error = assert_raises(Metacrunch::Elasticsearch::Error) { @search.ids({nonsense: {}}) }

    assert_equal "elasticsearch books: 400 parsing_exception: unknown query", error.message
  end

  def test_a_failed_connection_names_the_index
    @fake.on("GET", "/") { raise Faraday::ConnectionFailed, "Connection refused" }
    search = Search.new(@fake.connection(retries: 0), index: "books")
    error = assert_raises(Metacrunch::Elasticsearch::Error) { search.ids({match_all: {}}) }

    assert_equal "elasticsearch books: request to #{FakeElasticsearch::URL} failed: Connection refused", error.message
  end

  def test_validates_query_and_size
    query = assert_raises(ArgumentError) { @search.ids("isbn:1") }
    size = assert_raises(ArgumentError) { @search.hits({match_all: {}}, size: 0) }

    assert_equal ["query must be a Hash, got String", "size must be an Integer from 1 to 10000, got 0"],
                 [query.message, size.message]
  end

end
