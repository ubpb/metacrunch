# frozen_string_literal: true

module Metacrunch
  module Db
    # The name of a table for the reader and the writer: "books", or
    # "library.books" with its schema (on MySQL and MariaDB: its database).
    # Other names go through a query (Reader) or Sequel's identifiers.
    class Table

      WORD = /[A-Za-z_][A-Za-z0-9_$]*/
      NAME = /\A#{WORD}(?:\.#{WORD})?\z/

      # The name for Sequel: a Symbol, or a qualified identifier.
      attr_reader :identifier

      def initialize(name)
        unless (name.is_a?(String) || name.is_a?(Symbol)) && name.to_s.match?(NAME)
          raise ArgumentError, "table must be a name such as books or library.books, got #{name.inspect}"
        end

        @name = name.to_s
        schema, table = @name.split(".", 2)
        @identifier = table ? Sequel[schema.to_sym][table.to_sym] : schema.to_sym
      end

      def to_s = @name

    end
  end
end
