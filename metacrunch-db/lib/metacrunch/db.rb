# frozen_string_literal: true

require "sequel"
require "metacrunch"
require_relative "db/version"
require_relative "db/errors"

module Metacrunch
  # Relational databases for metacrunch, on Sequel: SQLite, PostgreSQL,
  # MySQL and MariaDB.
  module Db
  end
end
