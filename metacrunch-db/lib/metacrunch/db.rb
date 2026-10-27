# frozen_string_literal: true

require "sequel"
require "metacrunch"
require_relative "db/version"
require_relative "db/errors"
require_relative "db/table"
require_relative "db/connection"

module Metacrunch
  # Relational databases for metacrunch, on Sequel: SQLite, PostgreSQL,
  # MySQL and MariaDB.
  module Db

    PREFIX = /\A[a-z][a-z0-9_]*\z/

    # The connection params for jobs and commands, as a proc for
    # params { instance_exec(&Metacrunch::Db.connection_params) }, read by
    # Connection.from_params(params). With a prefix ("source") the names are
    # source_url, source_user and source_password, for a job with two
    # databases. The password is a secret; values from environment variables
    # or the credentials come from a params file.
    def self.connection_params(prefix = nil)
      unless prefix.nil? || (prefix.is_a?(String) && prefix.match?(PREFIX))
        raise ArgumentError, "prefix must be a lowercase word such as source, got #{prefix.inspect}"
      end

      name = ->(param) { prefix ? :"#{prefix}_#{param}" : param }
      what = prefix ? "#{prefix} database" : "database"
      proc do
        param name.call(:url), String,
              required: true, desc: "#{what} URL, e.g. postgres://host/db, mysql2://host/db or sqlite://books.db"
        param name.call(:user), String, desc: "#{what} user"
        secret name.call(:password), String, desc: "#{what} password"
      end
    end

    # url, user and password: params { instance_exec(&Metacrunch::Db::CONNECTION_PARAMS) }.
    CONNECTION_PARAMS = connection_params

  end
end
