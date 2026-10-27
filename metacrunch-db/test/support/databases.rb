# frozen_string_literal: true

# Helpers of the unit tests: SQLite databases in a temporary directory and
# connections to Sequel's mock adapter.
module Databases

  # A connection whose connect returns the given database, e.g.
  # Sequel.mock(host: "postgres"), for SQL that SQLite does not get.
  class FakeConnection

    attr_reader :connects

    def initialize(database)
      @database = database
      @connects = 0
    end

    def connect
      @connects += 1
      @database
    end

    def url = "mock://#{@database.database_type}"

    def inspect = "#<FakeConnection #{url}>"

  end

  # A module for Database#extend_datasets that records the calls of the
  # streaming methods and returns the dataset itself.
  class Streaming < Module

    attr_reader :calls

    def initialize(*methods)
      super()
      calls = @calls = []
      methods.each do |name|
        define_method(name) do |*args|
          calls << [name, *args]
          self
        end
      end
    end

  end

  def setup
    @dir = Dir.mktmpdir
    super
  end

  def teardown
    @databases&.each(&:disconnect)
    FileUtils.remove_entry(@dir) if @dir
    super
  end

  # A connection to a SQLite file in the test's directory.
  def sqlite_connection(name = "test", **) = Metacrunch::Db::Connection.new(url: "sqlite://#{@dir}/#{name}.db", **)

  # A database of the SQLite file, for setting up and checking tables; disconnected after the test.
  def sqlite(name = "test")
    (@databases ||= []) << sqlite_connection(name).connect
    @databases.last
  end

  def context(log = StringIO.new) = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log))

  # The table books with a row per Hash.
  def create_books(database, rows = [])
    database.create_table(:books) do
      String :isbn, primary_key: true
      String :title, null: false
      Integer :year
      BigDecimal :price, size: [10, 2]
      Date :published
      Time :updated_at
      TrueClass :available
    end
    database[:books].multi_insert(rows) unless rows.empty?
    database
  end

end
