# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include BulkAnswers

  Writer = Metacrunch::Elasticsearch::Writer

  def setup
    @fake = FakeElasticsearch.new
    @log = StringIO.new
  end

  def test_writes_a_batch_in_one_request
    serve_bulk(@fake)
    open_writer(id: "id").write_batch(books(1, 2, 3))
    request = @fake.calls.last

    assert_equal [["1", "2", "3"]], bulk_ids(@fake)
    assert_equal "errors,items.*.status,items.*.error", request.params["filter_path"]
  end

  def test_open_refuses_a_missing_index
    @fake.on("HEAD", "/books") { [404, nil] }
    error = assert_raises(Metacrunch::OutputError) { open_writer }

    assert_equal "elasticsearch books: no such index or alias", error.message
  end

  def test_open_refuses_a_closed_index
    serve_bulk(@fake)
    @fake.on("GET", "/_cat/indices/books") { [200, [{"index" => "books", "status" => "close"}]] }
    error = assert_raises(Metacrunch::OutputError) { open_writer }

    assert_equal "elasticsearch books: books is closed", error.message
  end

  def test_open_refuses_an_index_with_a_write_block
    serve_bulk(@fake)
    blocked = {"books" => {"settings" => {"index" => {"blocks" => {"write" => "true"}}}}}
    @fake.on("GET", "/books/_settings") { [200, blocked] }
    error = assert_raises(Metacrunch::OutputError) { open_writer }

    assert_equal "elasticsearch books: books (index.blocks.write) refuses writes", error.message
  end

  def test_behind_an_alias_with_a_write_index_only_that_index_is_checked
    serve_bulk(@fake)
    aliases = {"books-1" => {"aliases" => {"books" => {}}},
               "books-2" => {"aliases" => {"books" => {"is_write_index" => true}}}}
    @fake.on("GET", "/_alias/books") { [200, aliases] }
    open_writer

    assert_equal ["/_cat/indices/books-2", "/books-2/_settings"], @fake.calls.map(&:path).last(2)
  end

  def test_open_refuses_an_alias_of_several_indices_without_a_write_index
    serve_bulk(@fake)
    @fake.on("GET", "/_alias/books") do
      [200, {"books-2" => {"aliases" => {"books" => {}}}, "books-1" => {"aliases" => {"books" => {}}}}]
    end
    error = assert_raises(Metacrunch::OutputError) { open_writer }

    assert_equal "elasticsearch books: the alias points to books-1, books-2 and to none of them as its write index",
                 error.message
  end

  def test_an_alias_with_a_write_index_takes_the_records
    serve_bulk(@fake)
    @fake.on("GET", "/_alias/books") do
      [200,
       {"books-1" => {"aliases" => {"books" => {}}},
        "books-2" => {"aliases" => {"books" => {"is_write_index" => true}}}}]
    end

    assert_nil open_writer(id: "id").write_batch(books(1))
  end

  def test_items_refused_for_good_are_reported_with_their_position
    serve_bulk(@fake) { |_action, id| {"2" => 400, "3" => 409}[id] }
    error = assert_raises(Metacrunch::SinkFailures) { open_writer(id: "id").write_batch(books(1, 2, 3)) }

    assert_equal [1, 2], error.failed.keys
    assert_equal "400 document_parsing_exception: failed to parse field [year] (index 2)", error.failed[1].message
  end

  def test_records_that_cannot_be_sent_are_reported_with_the_refused_ones
    serve_bulk(@fake) { |_action, id| 400 if id == "3" }
    error = assert_raises(Metacrunch::SinkFailures) do
      open_writer(id: "id", action: :delete).write_batch([{"id" => "1"}, {"t" => "no id"}, {"id" => "3"}])
    end

    assert_equal([[1, Metacrunch::Elasticsearch::Error], [2, Metacrunch::Elasticsearch::BulkItemError]],
                 error.failed.map { |position, failure| [position, failure.class] })
  end

  def test_deleting_a_missing_document_counts_as_written
    serve_bulk(@fake) { 404 }

    assert_nil open_writer(id: "id", action: :delete).write_batch(books(1))
  end

  def test_items_refused_for_now_are_sent_again_alone
    rejected = ["2"]
    serve_bulk(@fake) { |_action, id| 429 if rejected.delete(id) }
    writer = open_writer(id: "id")
    delays = no_sleep(writer)
    writer.write_batch(books(1, 2, 3))

    assert_equal [["1", "2", "3"], ["2"]], bulk_ids(@fake)
    assert_equal [1.0], delays
    assert_match "WARN -- : elasticsearch books: bulk 429, retry 1/5 in 1.0 s", @log.string
  end

  def test_requests_refused_for_now_are_sent_again_with_a_growing_delay
    serve_bulk(@fake)
    @fake.on("POST", "/_bulk", times: 3) { [503, {"error" => {"type" => "x", "reason" => "y"}}] }
    writer = open_writer(id: "id")
    delays = no_sleep(writer)
    writer.write_batch(books(1))

    assert_equal [1.0, 2.0, 4.0], delays
    assert_equal 4, bulk_ids(@fake).size
  end

  def test_after_the_last_retry_the_run_stops
    serve_bulk(@fake) { 429 }
    writer = open_writer(id: "id", retries: 2)
    no_sleep(writer)
    error = assert_raises(Metacrunch::OutputError) { writer.write_batch(books(1, 2)) }

    assert_equal "elasticsearch books: 2 records still refused with 429 after 2 retries", error.message
  end

  def test_without_retries_one_refused_record_stops_the_run
    serve_bulk(@fake) { 503 }
    error = assert_raises(Metacrunch::OutputError) { open_writer(id: "id", retries: 0).write_batch(books(1)) }

    assert_equal "elasticsearch books: 1 record still refused with 503 after 0 retries", error.message
  end

  def test_a_refused_check_of_the_index_stops_the_run
    @fake.on("HEAD", "/books") { [403, nil] }
    error = assert_raises(Metacrunch::OutputError) { open_writer }

    assert_equal "elasticsearch books: 403; #{Metacrunch::Elasticsearch::Connection::AUTH_HINT}", error.message
  end

  def test_a_request_that_is_too_large_is_halved_and_a_single_document_fails
    serve_bulk(@fake)
    @fake.on("POST", "/_bulk") do |request|
      ids = bulk_actions(request).map { it.last["_id"] }
      if ids.size > 1 || ids == ["3"]
        [413,
         nil]
      else
        [200, {"errors" => false, "items" => [{"index" => {"status" => 201}}]}]
      end
    end
    error = assert_raises(Metacrunch::SinkFailures) { open_writer(id: "id").write_batch(books(1, 2, 3)) }

    assert_equal [["1", "2", "3"], ["1", "2"], ["1"], ["2"], ["3"]], bulk_ids(@fake)
    assert_equal({2 => 413}, error.failed.transform_values(&:status))
  end

  def test_batches_are_cut_into_requests_of_at_most_max_bytes
    serve_bulk(@fake)
    open_writer(id: "id", max_bytes: 150).write_batch(books(1, 2, 3))

    assert_equal [["1", "2"], ["3"]], bulk_ids(@fake)
  end

  def test_other_refused_requests_stop_the_run
    serve_bulk(@fake)
    @fake.on("POST", "/_bulk") { [400, {"error" => {"type" => "illegal_argument_exception", "reason" => "bad"}}] }
    error = assert_raises(Metacrunch::OutputError) { open_writer.write_batch(books(1)) }

    assert_equal "elasticsearch books: 400 illegal_argument_exception: bad", error.message
  end

  def test_a_failed_connection_stops_the_run
    @fake.on("GET", "/") { raise Faraday::ConnectionFailed, "Connection refused" }
    writer = Writer.new(@fake.connection(retries: 0), index: "books")
    error = assert_raises(Metacrunch::OutputError) { writer.write_batch(books(1)) }

    assert_equal "elasticsearch books: request to #{FakeElasticsearch::URL} failed: Connection refused", error.message
  end

  def test_a_lost_connection_while_writing_stops_the_run
    serve_bulk(@fake)
    @fake.on("POST", "/_bulk") { raise Faraday::ConnectionFailed, "Connection reset" }
    writer = Writer.new(@fake.connection(retries: 0), index: "books")
    error = assert_raises(Metacrunch::OutputError) { writer.write_batch(books(1)) }

    assert_equal "elasticsearch books: request to #{FakeElasticsearch::URL} failed: Connection reset", error.message
  end

  def test_write_sends_one_record_and_hints_at_batch_once
    serve_bulk(@fake)
    writer = open_writer
    2.times { writer.write({"t" => "a"}) }

    assert_equal 2, bulk_ids(@fake).size
    assert_equal 1, @log.string.scan("use `sink ..., batch: 1000`").size
  end

  def test_inspect_shows_no_credentials
    serve_bulk(@fake)
    writer = Writer.new(@fake.connection(user: "elastic", password: "secret"), index: "books")
    writer.open(Metacrunch::OpenContext.new(params: nil, logger: Logger.new(nil)))

    assert_equal "#<Metacrunch::Elasticsearch::Writer index=books connection=#<Metacrunch::Elasticsearch::Connection " \
                 "url=#{FakeElasticsearch::URL} user=elastic password=[FILTERED]>>", writer.inspect
  end

  def test_validates_its_options
    {
      {index: "Books"} => 'index "Books" is not a valid name: it has uppercase letters',
      {id: 1} => "id must be a key or a callable, got 1",
      {action: :replace} => "action must be one of :index, :create, :update, :upsert, :delete or a callable, " \
                            "got :replace",
      {max_bytes: 0} => "max_bytes must be a positive Integer, got 0",
      {retries: -1} => "retries must be an Integer of 0 or more, got -1"
    }.each do |options, message|
      error = assert_raises(ArgumentError) { Writer.new(@fake.connection, index: "books", **options) }

      assert_equal message, error.message
    end
  end

  private

  def books(*ids) = ids.map { {"id" => it.to_s, "title" => "Book #{it}"} }

  def open_writer(**)
    Writer.new(@fake.connection, index: "books", **).tap do |writer|
      writer.open(Metacrunch::OpenContext.new(params: nil, logger: Logger.new(@log)))
    end
  end

  # Records the delays instead of sleeping; the random part is always 1.
  def no_sleep(writer)
    [].tap do |delays|
      writer.define_singleton_method(:sleep) { |seconds| delays << seconds }
      writer.define_singleton_method(:rand) { 1.0 }
    end
  end

end
