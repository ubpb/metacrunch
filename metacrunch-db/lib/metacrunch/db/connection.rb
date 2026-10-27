# frozen_string_literal: true

module Metacrunch
  module Db
    # Where and how to reach a database. A value: building one does no I/O
    # and loads no driver. Every reader and writer opens a database of its
    # own from it (connect), so a reader and a writer of one job (two threads
    # with -w) share no connection.
    class Connection

      # The gem each of Sequel's adapters needs, for the message when it is
      # missing.
      GEMS = {
        "postgres" => "pg", "postgresql" => "pg", "mysql2" => "mysql2", "trilogy" => "trilogy",
        "sqlite" => "sqlite3", "oracle" => "ruby-oci8", "tinytds" => "tiny_tds"
      }.freeze
      SCHEME = /\A([a-z][a-z0-9+.-]*):/i
      # What follows sqlite: in a URL of an in-memory database.
      IN_MEMORY = ["", "/", ":memory:"].freeze
      PARAMS = [:url, :user, :password].freeze

      # A connection from the bound params of a job or command: the ones of
      # Db.connection_params(prefix) it declares.
      def self.from_params(params, prefix: nil)
        names = PARAMS.to_h { [it, prefix ? :"#{prefix}_#{it}" : it] }
        new(**names.select { |_, name| params.respond_to?(name) }.transform_values { params.public_send(it) })
      end

      # A URL for messages: user info (user:password@) as [FILTERED], up to the
      # last @, since a password may hold an unencoded @.
      def self.filter(url) = url.to_s.sub(%r{//.*@}, "//[FILTERED]@")

      # url: a Sequel URL (postgres://, mysql2://, trilogy://, sqlite://, ...),
      # a String or Pathname. user and password override nothing: with user
      # info in the URL they are an error. options go to Sequel.connect.
      def initialize(url:, user: nil, password: nil, **options)
        @url = database_url(url)
        @user = optional_string(user, :user)
        @password = optional_string(password, :password)
        if (@user || @password) && @url.match?(%r{\A[^/]*//[^/]*@})
          raise ArgumentError, "give user and password in url or as options, not both"
        end

        @options = options
      end

      # The URL for messages, user info filtered.
      def url = Connection.filter(@url)

      # A new Sequel::Database, checked with one connection; with a block, it
      # yields the database, disconnects it afterwards and returns the block's
      # value. Raises Error when the driver is missing or the connection
      # fails.
      def connect
        database = open_database
        return database unless block_given?

        begin
          yield database
        ensure
          database.disconnect
        end
      end

      def inspect
        parts = ["url=#{url}"]
        parts << "user=#{@user}" if @user
        parts << "password=[FILTERED]" if @password
        "#<#{self.class.name} #{parts.join(" ")}>"
      end

      alias to_s inspect

      private

      def open_database
        credentials = {user: @user, password: @password}.compact
        Sequel.connect(@url, **@options, **credentials, keep_reference: false, test: true)
      rescue Sequel::AdapterNotFound
        raise Error, missing_adapter
      rescue Sequel::Error => e
        raise Error, "#{url}: #{e.message}"
      end

      def missing_adapter
        scheme = @url[SCHEME, 1]
        gem = GEMS[scheme]
        return "#{url}: the adapter #{scheme} needs the gem #{gem}; add it to the Gemfile" if gem

        "#{url}: no Sequel adapter for #{scheme}://"
      end

      def database_url(value)
        url = value.is_a?(Pathname) ? value.to_s : value
        unless url.is_a?(String) && url.match?(SCHEME)
          raise ArgumentError, "url must be a database URL such as postgres://host/db, mysql2://host/db or " \
                               "sqlite://books.db, got #{Connection.filter(value).inspect}"
        end
        if url.match?(/\Asqlite:/i) && IN_MEMORY.include?(url.sub(/\Asqlite:/i, "").delete_prefix("//"))
          raise ArgumentError, "an in-memory SQLite database lives in one connection, and every reader and writer " \
                               "opens its own; use a file"
        end

        url
      end

      def optional_string(value, name)
        return value if value.nil? || (value.is_a?(String) && !value.empty?)

        raise ArgumentError, "#{name} must be a non-empty String"
      end

    end
  end
end
