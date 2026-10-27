# frozen_string_literal: true

# For the tests in test/integration: each runs against SQLite and against every server whose URL is set,
# TEST_POSTGRES_URL, TEST_MYSQL_URL and TEST_MARIADB_URL (see test/compose.yml); MySQL and MariaDB once per driver
# the bundle has (mysql2, trilogy).
module Integration

  Target = Data.define(:name, :url)

  # The servers: the variable of the URL and the URL schemes of their drivers, with the gem of each.
  SERVERS = {
    "postgres" => ["TEST_POSTGRES_URL", {"postgres" => "pg"}],
    "mysql" => ["TEST_MYSQL_URL", {"mysql2" => "mysql2", "trilogy" => "trilogy"}],
    "mariadb" => ["TEST_MARIADB_URL", {"mysql2" => "mysql2", "trilogy" => "trilogy"}]
  }.freeze

  def self.servers? = SERVERS.each_value.any? { |variable, _| !ENV.fetch(variable, "").empty? }

  # SQLite (url nil: a file per test), then each server and driver.
  def self.targets
    servers = SERVERS.flat_map do |server, (variable, drivers)|
      url = ENV.fetch(variable, "")
      next [] if url.empty?

      drivers.select { |_, gem| Gem.loaded_specs.key?(gem) }.map do |scheme, _|
        Target.new(name: drivers.size > 1 ? "#{server}_#{scheme}" : server, url: url.sub(/\A[a-z0-9+]+:/, "#{scheme}:"))
      end
    end
    [Target.new(name: "sqlite", url: nil), *servers]
  end

  # A test class per target, named after base and the target (ReadingPostgresTest), with the tests of tests.
  def self.define(base, tests)
    targets.each do |target|
      test_class = Class.new(Minitest::Test) do
        include Helpers
        include tests

        define_method(:target) { target }
      end
      Object.const_set("#{base}#{target.name.split("_").map(&:capitalize).join}Test", test_class)
    end
  end

  # The test's tables have a prefix of their own and are dropped afterwards.
  module Helpers

    attr_reader :database

    def setup
      @dir = Dir.mktmpdir
      @prefix = "metacrunch_test_#{SecureRandom.hex(3)}_"
      @url = target.url || "sqlite://#{@dir}/test.db"
      @database = connection.connect
      super
    end

    def teardown
      @database.tables.select { it.to_s.start_with?(@prefix) }.each { @database.drop_table(it) }
      @database.disconnect
      FileUtils.remove_entry(@dir)
      super
    end

    def connection = Metacrunch::Db::Connection.new(url: @url)

    def table(name) = "#{@prefix}#{name}"

    def type = @database.database_type

    def context = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(StringIO.new))

    # The table books (isbn, title, year) with a row per Hash.
    def create_books(rows = [], name: table("books"))
      @database.create_table(name.to_sym) do
        String :isbn, primary_key: true, size: 20
        String :title, size: 100
        Integer :year
      end
      @database[name.to_sym].multi_insert(rows) unless rows.empty?
      name
    end

    def stored(name = table("books")) = @database[name.to_sym].order(:isbn).select_map([:isbn, :title, :year])

    # Writes records with a writer of options, opened and closed as in a job.
    def write(records, connection: self.connection, **)
      writer = Metacrunch::Db::Writer.new(connection, **)
      writer.open(context)
      writer.write_batch(records)
    ensure
      writer&.close
    end

    # The schema of the test's tables; on MySQL and MariaDB the database.
    def schema
      case type
      when :postgres then "public"
      when :mysql then database.get(Sequel.function(:database))
      else "main"
      end
    end

    # A lock that is not released fails at once instead of blocking the test.
    def lock_timeout
      case type
      when :postgres then database.run("SET lock_timeout = '5s'")
      when :mysql then database.run("SET SESSION lock_wait_timeout = 5")
      end
    end

  end

end
