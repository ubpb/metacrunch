# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class CommandsTest < Minitest::Test

  include Pages

  NAMES = ["es:create-index", "es:delete-index", "es:finish-load", "es:list", "es:prune", "es:switch-alias",
           "es:update-settings"].freeze

  def setup
    @fake = FakeElasticsearch.new
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_the_gem_ships_these_commands
    names = Dir[Metacrunch::Elasticsearch::COMMANDS].map { Metacrunch.load_command(it).name }

    assert_equal NAMES, names.sort
  end

  def test_create_index_by_name_with_settings_and_mappings_from_files
    @fake.on("PUT", "/books") { [200, {"acknowledged" => true}] }
    settings = file("settings.jsonc", %({"number_of_shards": 1, // one is enough\n}))
    mappings = file("mappings.json", %({"properties": {"title": {"type": "text"}}}))
    run = invoke("es:create-index", name: ["books"], settings:, mappings:, bulk_load: true)

    assert_equal "books", run.value
    assert_equal({"index.number_of_shards" => 1, "index.refresh_interval" => "-1", "index.number_of_replicas" => 0},
                 @fake.calls.last.json["settings"])
  end

  def test_create_index_for_an_alias
    @fake.on("PUT", %r{\A/books-\d{8}-\d{6}\z}) { [200, {"acknowledged" => true}] }

    assert_match(/\Abooks-\d{8}-\d{6}\z/, invoke("es:create-index", alias: "books").value)
  end

  def test_create_index_skips_an_existing_index_when_asked
    @fake.on("HEAD", "/books") { [200, nil] }

    assert_equal "books", invoke("es:create-index", name: ["books"], skip_existing: true).value
    assert_equal(["HEAD"], @fake.calls.map(&:verb))
  end

  def test_create_index_needs_name_or_alias
    errors = [{}, {name: ["books"], alias: "books"}, {alias: "books", skip_existing: true}].map do |params|
      invoke("es:create-index", **params).error
    end

    assert_equal (["es:create-index needs NAME or --alias, not both"] * 2) + ["--skip-existing works with NAME only"],
                 errors.map(&:message)
    assert_equal [Metacrunch::ParamError], errors.map(&:class).uniq
  end

  def test_invalid_names_and_keep_are_param_errors
    runs = [invoke("es:create-index", name: ["Books"]), invoke("es:finish-load", index: ["books*"]),
            invoke("es:switch-alias", names: ["books", "_books"]), invoke("es:prune", alias: ["books"], keep: -1),
            invoke("es:delete-index", name: ["a b"]), invoke("es:update-settings", index: ["Books"], settings: "s")]
    errors = runs.map(&:error)

    assert_equal [Metacrunch::ParamError], errors.map(&:class).uniq
    assert_equal ['index "Books" is not a valid name: it has uppercase letters', "--keep must be 0 or more, got -1"],
                 errors.values_at(0, 3).map(&:message)
  end

  def test_finish_load
    @fake.on("PUT", "/books/_settings") { [200, {"acknowledged" => true}] }
    @fake.on("POST", "/books/_refresh") { [200, {}] }
    invoke("es:finish-load", index: ["books"], settings: file("s.json", %({"number_of_replicas": 1})))

    assert_equal({"index.refresh_interval" => nil, "index.number_of_replicas" => 1}, @fake.calls.first.json)
  end

  def test_switch_alias
    @fake.on("HEAD", "/books-2") { [200, nil] }
    @fake.on("GET", "/_alias/books") { [200, {"books-1" => {"aliases" => {"books" => {}}}}] }
    @fake.on("POST", "/_aliases") { [200, {"acknowledged" => true}] }

    assert_equal ["books-1"], invoke("es:switch-alias", names: ["books", "books-2"]).value
  end

  def test_prune
    @fake.on("GET", "/_alias/books") { [200, {"books-20261020-000000" => {"aliases" => {"books" => {}}}}] }
    @fake.on("GET", "/_cat/indices/books-*") do
      [200, [{"index" => "books-20261001-000000"}, {"index" => "books-20261020-000000"}]]
    end

    assert_equal ["books-20261001-000000"], invoke("es:prune", alias: ["books"], keep: 0, dry_run: true).value
  end

  def test_delete_index
    @fake.on("GET", "/_alias/books-1") { [404, {"error" => "alias [books-1] missing", "status" => 404}] }
    @fake.on("GET", "/books-1/_alias") { [200, {"books-1" => {"aliases" => {"books" => {}}}}] }
    @fake.on("DELETE", "/books-1") { [200, {"acknowledged" => true}] }

    assert_instance_of Metacrunch::Elasticsearch::Error, invoke("es:delete-index", name: ["books-1"]).error
    assert_equal "books-1", invoke("es:delete-index", name: ["books-1"], force: true).value
  end

  def test_update_settings
    @fake.on("POST", "/books/_close") { [200, {}] }
    @fake.on("PUT", "/books/_settings") { [200, {"acknowledged" => true}] }
    @fake.on("POST", "/books/_open") { [200, {}] }
    invoke("es:update-settings", index: ["books"], settings: file("s.json", %({"number_of_shards": 2, "a": 1})),
                                 reopen: true)

    assert_equal ["/books/_close", "/books/_settings", "/books/_open"], @fake.calls.map(&:path)
    assert_equal({"index.a" => 1}, @fake.calls[1].json)
  end

  def test_list_prints_a_table
    @fake.on("GET", "/_cat/indices/books*") { [200, [{"index" => "books-1", "docs.count" => "3"}]] }
    @fake.on("GET", "/_cat/aliases") { [200, []] }
    out, = capture_io { invoke("es:list", pattern: ["books*"]) }

    assert_equal "index    aliases  docs  size  health  created\nbooks-1           3\n", out
  end

  private

  def invoke(name, **params)
    command = Metacrunch.load_command(File.join(File.dirname(Metacrunch::Elasticsearch::COMMANDS),
                                                "#{name.delete_prefix("es:").tr("-", "_")}.rb"))
    FakeConnections.use(@fake) { Metacrunch::Testing.invoke(command, params:) }
  end

  def file(name, text)
    File.join(@dir, name).tap { File.write(it, text) }
  end

end
