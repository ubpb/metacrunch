# frozen_string_literal: true

require "test_helper"

class ConnectionTest < Minitest::Test

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_url_needs_a_scheme
    error = assert_raises(ArgumentError) { connection(url: "books.db") }

    assert_equal "url must be a database URL such as postgres://host/db, mysql2://host/db or sqlite://books.db, " \
                 "got \"books.db\"", error.message
  end

  def test_a_url_must_be_a_string_or_pathname
    assert_raises(ArgumentError) { connection(url: nil) }
    assert_raises(ArgumentError) { connection(url: 42) }
  end

  def test_a_pathname_url_is_taken
    assert_equal "sqlite://#{@dir}/books.db", connection(url: Pathname("sqlite://#{@dir}/books.db")).url
  end

  def test_in_memory_sqlite_is_refused
    ["sqlite:/", "sqlite://", "sqlite::memory:", "sqlite:"].each do |url|
      error = assert_raises(ArgumentError) { connection(url:) }

      assert_equal "an in-memory SQLite database lives in one connection, and every reader and writer opens its " \
                   "own; use a file", error.message
    end
  end

  def test_user_info_and_user_options_exclude_each_other
    error = assert_raises(ArgumentError) { connection(url: "postgres://etl:secret@db/catalog", user: "etl") }

    assert_equal "give user and password in url or as options, not both", error.message
    assert_raises(ArgumentError) { connection(url: "postgres://etl@db/catalog", password: "secret") }
  end

  def test_user_and_password_must_be_non_empty_strings
    assert_raises(ArgumentError) { connection(url: "postgres://db/catalog", user: "") }
    error = assert_raises(ArgumentError) { connection(url: "postgres://db/catalog", password: 42) }

    assert_equal "password must be a non-empty String", error.message
  end

  def test_url_filters_user_info
    assert_equal "postgres://[FILTERED]@db/catalog", connection(url: "postgres://etl:p@ss@db/catalog").url
    assert_equal "postgres://db/catalog", connection(url: "postgres://db/catalog").url
  end

  def test_url_filters_passwords_in_the_query
    connection = connection(url: "mysql2://db/x?user=root&password=s3cret&sslpassword=k3y&encoding=utf8mb4")

    assert_equal "mysql2://db/x?user=root&password=[FILTERED]&sslpassword=[FILTERED]&encoding=utf8mb4", connection.url
    refute_includes connection.inspect, "s3cret"
  end

  def test_inspect_hides_the_password
    with_info = connection(url: "postgres://etl:secret@db/catalog")
    with_options = connection(url: "postgres://db/catalog", user: "etl", password: "secret")

    assert_equal "#<Metacrunch::Db::Connection url=postgres://[FILTERED]@db/catalog>", with_info.inspect
    assert_equal "#<Metacrunch::Db::Connection url=postgres://db/catalog user=etl password=[FILTERED]>",
                 with_options.to_s
  end

  def test_building_connects_nowhere
    assert_equal "postgres://nowhere.invalid/catalog", connection(url: "postgres://nowhere.invalid/catalog").url
  end

  def test_connect_returns_a_database_kept_out_of_sequel_databases
    before = Sequel::DATABASES.size
    database = sqlite.connect

    assert_kind_of Sequel::Database, database
    assert_equal 1, database.get(Sequel.lit("1"))
    assert_equal before, Sequel::DATABASES.size
  ensure
    database&.disconnect
  end

  def test_connect_passes_options_to_sequel
    database = sqlite(max_connections: 2).connect

    assert_equal 2, database.pool.max_size
  ensure
    database&.disconnect
  end

  def test_connect_passes_user_and_password
    options = nil
    stub_connect(->(url, **opts) { options = [url, opts] }) do
      connection(url: "postgres://db/catalog", user: "etl", password: "secret").connect
    end

    assert_equal "postgres://db/catalog", options[0]
    assert_equal({user: "etl", password: "secret", keep_reference: false, test: true}, options[1])
  end

  def test_connect_with_a_block_disconnects_and_returns_its_value
    kept = nil
    value = sqlite.connect do |database|
      kept = database
      database.get(Sequel.lit("2"))
    end

    assert_equal 2, value
    assert_equal 0, kept.pool.size
  end

  def test_a_missing_driver_names_the_gem
    error = stub_connect(->(*, **) { raise Sequel::AdapterNotFound, "LoadError: cannot load such file -- oci8" }) do
      assert_raises(Metacrunch::Db::Error) { connection(url: "oracle://etl:secret@db/x").connect }
    end

    assert_equal "oracle://[FILTERED]@db/x: the adapter oracle needs the gem ruby-oci8; add it to the Gemfile",
                 error.message
    assert_kind_of Sequel::AdapterNotFound, error.cause
  end

  def test_an_unknown_adapter_is_named
    error = assert_raises(Metacrunch::Db::Error) { connection(url: "nosuch://db/x").connect }

    assert_equal "nosuch://db/x: no Sequel adapter for nosuch://", error.message
  end

  def test_a_failed_connection_raises_db_error_with_the_url
    url = "sqlite://#{@dir}/missing/books.db"
    error = assert_raises(Metacrunch::Db::Error) { connection(url:).connect }

    assert_match(/\A#{Regexp.escape(url)}: /, error.message)
    assert_kind_of Sequel::DatabaseConnectionError, error.cause
  end

  def test_other_sequel_errors_raise_db_error
    error = stub_connect(->(*, **) { raise Sequel::Error, "invalid option" }) do
      assert_raises(Metacrunch::Db::Error) { connection(url: "postgres://db/x").connect }
    end

    assert_equal "postgres://db/x: invalid option", error.message
  end

  private

  def connection(**) = Metacrunch::Db::Connection.new(**)

  def sqlite(**) = connection(url: "sqlite://#{@dir}/books.db", **)

  # Replaces Sequel.connect while the block runs; quiet, since -w warns about the redefinition.
  def stub_connect(replacement)
    original = Sequel.method(:connect)
    quietly { Sequel.define_singleton_method(:connect, replacement) }
    yield
  ensure
    quietly { Sequel.define_singleton_method(:connect, original) }
  end

  def quietly
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

end
