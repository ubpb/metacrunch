# frozen_string_literal: true

require "test_helper"

class FullLoadTest < Minitest::Test

  include Integration

  SETTINGS = <<~JSONC
    {
      "number_of_shards": 1,
      "number_of_replicas": 0, // one node
      "analysis": {
        "analyzer": {"folding": {"tokenizer": "standard", "filter": ["lowercase", "asciifolding",]}},
      },
    }
  JSONC
  MAPPINGS = %({"properties": {"title": {"type": "text", "analyzer": "folding"}, "year": {"type": "integer"}}})

  def setup
    super
    @dir = Dir.mktmpdir
    @settings = File.join(@dir, "settings.jsonc").tap { File.write(it, SETTINGS) }
    @mappings = File.join(@dir, "mappings.json").tap { File.write(it, MAPPINGS) }
    @indices = Metacrunch::Elasticsearch::Indices.new(connection, logger: Logger.new(nil))
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
    super
  end

  def test_a_full_load_behind_an_alias
    old = load_index("#{@index}-20260101-000000", [{"id" => "1", "title" => "Émile"}])
    @indices.switch_alias(@index_alias = "#{@index}-books", old)
    new = load_index("#{@index}-books-20260102-000000", [{"id" => "2", "title" => "Zoë"}])
    previous = @indices.switch_alias(@index_alias, new)

    assert_equal [[old], [new]], [previous, @indices.aliased(@index_alias)]
    assert_equal ["2"], stored(@index_alias).keys
  end

  def test_bulk_load_settings_and_finish_load
    name = @indices.create("#{@index}-20260101-000000", settings: @settings, mappings: @mappings, bulk_load: true)
    during = index_settings(name)
    @indices.finish_load(name, settings: @settings)

    assert_equal ["-1", "0"], during
    assert_equal [nil, "0"], index_settings(name)
  end

  def test_the_analyzer_from_the_settings_file
    name = load_index("#{@index}-20260101-000000", [{"id" => "1", "title" => "Émile Zola"}])
    hits = client.search(index: name, body: {query: {match: {title: "emile"}}}).body.dig("hits", "hits")

    assert_equal(["1"], hits.map { it["_id"] })
  end

  def test_prune_deletes_older_indices_and_leaves_newer_ones
    books = "#{@index}-books"
    names = ["01", "02", "03", "04"].map { @indices.create("#{books}-202601#{it}-000000") }
    @indices.switch_alias(books, names[2])

    assert_equal [names[0]], @indices.prune(books, keep: 1)
    assert_equal(names[1..], @indices.list("#{books}-*").map { it[:name] })
  end

  def test_update_settings_with_reopen_changes_an_analyzer
    name = @indices.create(@index, settings: @settings)
    @indices.update_settings(name, {analysis: {analyzer: {folding: {tokenizer: "standard", filter: ["lowercase"]}}}},
                             reopen: true)
    filters = client.indices.get_settings(index: name).body.dig(name, "settings", "index", "analysis", "analyzer",
                                                                "folding", "filter")

    assert_equal ["lowercase"], filters
  end

  def test_delete_refuses_an_index_behind_an_alias
    name = @indices.create(@index)
    @indices.switch_alias("#{@index}-books", name)

    assert_raises(Metacrunch::Elasticsearch::Error) { @indices.delete(name) }
    assert_equal name, @indices.delete(name, force: true)
  end

  private

  def load_index(name, documents)
    @indices.create(name, settings: @settings, mappings: @mappings, bulk_load: true)
    Metacrunch::Elasticsearch::Writer.new(connection, index: name, id: "id").tap { it.open(context) }
                                     .write_batch(documents)
    @indices.finish_load(name, settings: @settings)
    name
  end

  def index_settings(name)
    client.indices.get_settings(index: name).body.dig(name, "settings", "index")
          .values_at("refresh_interval", "number_of_replicas")
  end

end
