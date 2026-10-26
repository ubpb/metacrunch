# frozen_string_literal: true

require "test_helper"

class IndicesTest < Minitest::Test

  Indices = Metacrunch::Elasticsearch::Indices
  Error = Metacrunch::Elasticsearch::Error
  MISSING_ALIAS = {"error" => "alias [books] missing", "status" => 404}.freeze

  def setup
    @fake = FakeElasticsearch.new
    @log = StringIO.new
    @indices = Indices.new(@fake.connection, logger: Logger.new(@log))
  end

  def test_create_sends_flat_settings_and_mappings
    @fake.on("PUT", "/books") { [200, {"acknowledged" => true}] }
    name = @indices.create("books", settings: {number_of_shards: 1, analysis: {analyzer: {}}},
                                    mappings: {properties: {title: {type: "text"}}})

    assert_equal "books", name
    assert_equal({"settings" => {"index.number_of_shards" => 1},
                  "mappings" => {"properties" => {"title" => {"type" => "text"}}}}, @fake.calls.last.json)
  end

  def test_create_for_a_bulk_load_names_the_index_after_the_alias_and_the_time
    @fake.on("PUT", %r{\A/books-\d{8}-\d{6}\z}) { [200, {"acknowledged" => true}] }
    name = @indices.create_for("books", settings: {"index.number_of_replicas" => 2}, bulk_load: true)

    assert_match(/\Abooks-\d{8}-\d{6}\z/, name)
    assert_equal({"settings" => {"index.number_of_replicas" => 0, "index.refresh_interval" => "-1"}},
                 @fake.calls.last.json)
    assert_match "INFO -- : created #{name}", @log.string
  end

  def test_create_refuses_an_existing_index
    @fake.on("PUT", "/books") do
      [400, {"error" => {"type" => "resource_already_exists_exception", "reason" => "index [books] already exists"}}]
    end
    error = assert_raises(Error) { @indices.create("books") }

    assert_equal "elasticsearch: 400 resource_already_exists_exception: index [books] already exists", error.message
  end

  def test_finish_load_puts_back_the_definition_s_values_and_refreshes
    @fake.on("PUT", "/books/_settings") { [200, {"acknowledged" => true}] }
    @fake.on("POST", "/books/_refresh") { [200, {}] }
    @indices.finish_load("books", settings: {index: {number_of_replicas: 2}})

    assert_equal({"index.refresh_interval" => nil, "index.number_of_replicas" => 2}, @fake.calls.first.json)
    assert_equal "/books/_refresh", @fake.calls.last.path
  end

  def test_switch_alias_moves_the_alias_in_one_request
    serve_alias("books" => ["books-1"])
    @fake.on("HEAD", "/books-2") { [200, nil] }
    previous = @indices.switch_alias("books", "books-2")

    assert_equal ["books-1"], previous
    assert_equal({"actions" => [{"remove" => {"index" => "books-1", "alias" => "books"}},
                                {"add" => {"index" => "books-2", "alias" => "books"}}]}, @fake.calls.last.json)
    assert_match "books: books-1 → books-2", @log.string
  end

  def test_switch_alias_adds_a_new_alias
    serve_alias
    @fake.on("HEAD", "/books-1") { [200, nil] }
    @fake.on("HEAD", "/books") { [404, nil] }

    assert_empty @indices.switch_alias("books", "books-1")
    assert_equal({"actions" => [{"add" => {"index" => "books-1", "alias" => "books"}}]}, @fake.calls.last.json)
  end

  def test_switch_alias_does_nothing_when_the_alias_points_there_alone
    serve_alias("books" => ["books-1"])
    @fake.on("HEAD", "/books-1") { [200, nil] }

    assert_equal ["books-1"], @indices.switch_alias("books", "books-1")
    refute(@fake.calls.any? { it.path == "/_aliases" })
  end

  def test_switch_alias_refuses_a_missing_index
    @fake.on("HEAD", "/books-9") { [404, nil] }
    error = assert_raises(Error) { @indices.switch_alias("books", "books-9") }

    assert_equal "elasticsearch: books-9: no such index", error.message
  end

  def test_switch_alias_refuses_an_index_with_the_alias_name
    serve_alias
    @fake.on("HEAD", "/books-1") { [200, nil] }
    @fake.on("HEAD", "/books") { [200, nil] }
    error = assert_raises(Error) { @indices.switch_alias("books", "books-1") }

    assert_equal "elasticsearch: books is an index, not an alias; delete it before the alias can take its name",
                 error.message
  end

  def test_prune_deletes_older_indices_but_keeps_the_newest_of_them
    serve_prune
    deleted = @indices.prune("books", keep: 1)

    assert_equal ["books-20261001-000000"], deleted
    assert_equal(["/books-20261001-000000"], @fake.calls.select { it.verb == "DELETE" }.map(&:path))
    assert_match "books-20261030-000000 is newer than books-20261020-000000, left alone", @log.string
  end

  def test_prune_with_dry_run_deletes_nothing
    serve_prune

    assert_equal ["books-20261001-000000", "books-20261010-000000"], @indices.prune("books", keep: 0, dry_run: true)
    refute(@fake.calls.any? { it.verb == "DELETE" })
  end

  def test_prune_needs_a_timestamped_index_behind_the_alias
    serve_alias

    assert_equal "elasticsearch: no index behind books, so nothing is pruned",
                 assert_raises(Error) { @indices.prune("books") }.message
    serve_alias("books" => ["books-v1"])

    assert_empty @indices.prune("books")
  end

  def test_prune_keeps_a_number_of_indices
    error = assert_raises(ArgumentError) { @indices.prune("books", keep: -1) }

    assert_equal "keep must be an Integer of 0 or more, got -1", error.message
  end

  def test_errors_of_the_alias_lookup_other_than_a_missing_alias_pass
    @fake.on("GET", "/_alias/books") { [500, {"error" => {"type" => "x", "reason" => "y"}}] }

    assert_equal "elasticsearch: 500 x: y", assert_raises(Error) { @indices.aliased("books") }.message
  end

  def test_update_settings_leaves_out_the_number_of_shards
    @fake.on("PUT", "/books/_settings") { [200, {"acknowledged" => true}] }
    @indices.update_settings("books", {number_of_shards: 3, number_of_replicas: 1})

    assert_equal({"index.number_of_replicas" => 1}, @fake.calls.last.json)
  end

  def test_update_settings_with_reopen_opens_the_index_also_after_a_failure
    @fake.on("POST", "/books/_close") { [200, {}] }
    @fake.on("POST", "/books/_open") { [200, {}] }
    @fake.on("PUT", "/books/_settings") do
      [400, {"error" => {"type" => "illegal_argument_exception", "reason" => "bad"}}]
    end

    assert_raises(Error) do
      @indices.update_settings("books", {analysis: {analyzer: {a: {type: "custom"}}}}, reopen: true)
    end
    assert_equal ["/books/_close", "/books/_settings", "/books/_open"], @fake.calls.map(&:path)
  end

  def test_update_settings_explains_settings_that_need_a_closed_index
    @fake.on("PUT", "/books/_settings") do
      [400, {"error" => {"type" => "illegal_argument_exception",
                         "reason" => "Can't update non dynamic settings [[index.analysis.analyzer.a.type]]"}}]
    end
    error = assert_raises(Error) { @indices.update_settings("books", {"analysis.analyzer.a.type" => "custom"}) }

    assert_match(/non dynamic settings .*; use reopen \(--reopen\)/, error.message)
    assert_raises(ArgumentError) { @indices.update_settings("books", {number_of_shards: 3}) }
  end

  def test_delete_refuses_an_index_an_alias_points_to_unless_forced
    serve_alias
    @fake.on("GET", "/books-1/_alias") { [200, {"books-1" => {"aliases" => {"books" => {}}}}] }
    @fake.on("DELETE", "/books-1") { [200, {"acknowledged" => true}] }
    error = assert_raises(Error) { @indices.delete("books-1") }

    assert_equal "elasticsearch: books points to books-1; switch it first or use force", error.message
    assert_equal "books-1", @indices.delete("books-1", force: true)
  end

  def test_delete_names_every_alias_of_the_index
    serve_alias
    @fake.on("GET", "/books-1/_alias") { [200, {"books-1" => {"aliases" => {"books" => {}, "titles" => {}}}}] }
    error = assert_raises(Error) { @indices.delete("books-1") }

    assert_equal "elasticsearch: books, titles point to books-1; switch them first or use force", error.message
  end

  def test_delete_refuses_an_alias
    serve_alias("books-1" => ["books-20261026-000000"])

    assert_equal "elasticsearch: books-1 is an alias; delete the index behind it",
                 assert_raises(Error) { @indices.delete("books-1") }.message
  end

  def test_list_and_table
    @fake.on("GET", "/_cat/indices/*") do
      [200, [{"index" => "books-2", "health" => "green", "docs.count" => "1200", "store.size" => "3565158",
              "creation.date" => (Time.utc(2026, 10, 26).to_i * 1000).to_s},
             {"index" => "books-1", "health" => nil, "docs.count" => nil, "store.size" => nil, "creation.date" => nil}]]
    end
    @fake.on("GET", "/_cat/aliases") { [200, [{"alias" => "books", "index" => "books-2"}]] }
    rows = @indices.list
    summary = rows.map { it.values_at(:name, :aliases, :docs) }

    assert_equal [["books-1", [], nil], ["books-2", ["books"], 1200]], summary
    assert_equal <<~TABLE.chomp, Indices.table(rows)
      index    aliases  docs  size    health  created
      books-1
      books-2  books    1200  3.4 MB  green   2026-10-26 00:00
    TABLE
  end

  def test_sizes_for_people
    assert_equal(["", "512 B", "2.0 KB", "1.5 GB"], [nil, 512, 2048, 1_610_612_736].map { Indices.size(it) })
  end

  def test_inspect_shows_no_credentials
    @fake.on("HEAD", "/books") { [200, nil] }
    indices = Indices.new(@fake.connection(api_key: "k3y"))
    indices.exists?("books")

    assert_equal "#<Metacrunch::Elasticsearch::Indices connection=#<Metacrunch::Elasticsearch::Connection " \
                 "url=#{FakeElasticsearch::URL} api_key=[FILTERED]>>", indices.inspect
  end

  def test_failures_name_elasticsearch
    @fake.on("GET", "/") { raise Faraday::ConnectionFailed, "Connection refused" }
    indices = Indices.new(@fake.connection(retries: 0))

    assert_equal "elasticsearch: request to #{FakeElasticsearch::URL} failed: Connection refused",
                 assert_raises(Error) { indices.exists?("books") }.message
  end

  private

  # GET /_alias/NAME for each alias and its indices; 404 for others. And the
  # changes of aliases.
  def serve_alias(aliases = {})
    @fake.on("POST", "/_aliases") { [200, {"acknowledged" => true}] }
    @fake.on("GET", %r{\A/_alias/}) do |request|
      name = request.path.delete_prefix("/_alias/")
      indices = aliases[name]
      indices ? [200, indices.to_h { [it, {"aliases" => {name => {}}}] }] : [404, MISSING_ALIAS]
    end
  end

  def serve_prune
    serve_alias("books" => ["books-20261020-000000"])
    @fake.on("GET", "/_cat/indices/books-*") do
      [200, ["books-20261001-000000", "books-20261010-000000", "books-20261020-000000", "books-20261030-000000",
             "books-extra", "books-x-20261001-000000"].map { {"index" => it} }]
    end
    @fake.on("DELETE", %r{\A/books-}) { [200, {"acknowledged" => true}] }
  end

end
