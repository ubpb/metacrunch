# frozen_string_literal: true

module Metacrunch
  module Db

    # The actions of the writer.
    ACTIONS = [:insert, :upsert, :update, :delete].freeze

    # The checks of a record before the writer builds SQL from it. Sequel
    # would write a Hash as a condition, an Array as a list and a Symbol as a
    # column name, so only plain values pass, and objects that Sequel writes
    # itself (sql_literal_append: its expressions and the wrappers of its
    # extensions, such as Sequel.pg_array).
    module Values

      PLAIN = [Integer, Float, BigDecimal, TrueClass, FalseClass, NilClass, Date, Time].freeze

      module_function

      # The row of a record: {column => value} with Symbol columns; for
      # :delete only the key columns, the others unchecked. columns: the table's columns (a Set of
      # Symbols), nil to skip the column check; key: an Array of Symbols, nil
      # for inserts. Raises Error for a record the writer cannot write.
      def row(record, table:, columns:, key:, action:)
        raise Error, "record is #{described(record)}, not a Hash" unless record.is_a?(Hash)
        raise Error, "record has no columns" if record.empty?

        row = columns_of(record)
        check_key(row, key) unless action == :insert
        row = row.slice(*key) if action == :delete
        check_columns(row, table, columns)
        row.each { |column, value| check(column, value) }
        row
      end

      # "a Hash", "an Array".
      def described(value)
        name = value.class.name
        "#{name.match?(/\A[AEIOU]/) ? "an" : "a"} #{name}"
      end

      def columns_of(record)
        record.each_with_object({}) do |(name, value), row|
          unless name.is_a?(String) || name.is_a?(Symbol)
            raise Error, "record has the key #{name.inspect} (#{described(name)}); keys are column names"
          end

          column = name.to_sym
          raise Error, "#{column} is given twice" if row.key?(column)

          row[column] = value
        end
      end

      def check_columns(row, table, columns)
        return unless columns

        unknown = row.keys.reject { columns.include?(it) }
        return if unknown.empty?

        raise Error, "#{table} has no column#{"s" if unknown.size > 1} #{unknown.join(", ")}"
      end

      def check_key(row, key)
        missing = key.find { row[it].nil? }
        raise Error, "no value for key #{missing}" if missing
      end

      def check(column, value)
        case value
        when String
          raise Error, "#{column} is not valid #{value.encoding}" unless value.valid_encoding?
        when *PLAIN then nil
        when Hash, Array
          raise Error, "#{column} is #{described(value)}; write JSON.generate(value) for a JSON column"
        when Symbol then raise Error, "#{column} is a Symbol; write a String"
        else
          return if value.respond_to?(:sql_literal_append)

          raise Error, "#{column} is #{described(value)}; turn it into a String or a number in a step"
        end
      end

    end

  end
end
