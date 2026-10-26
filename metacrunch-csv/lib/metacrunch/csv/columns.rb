# frozen_string_literal: true

module Metacrunch
  module Csv
    # Turns records into rows: the columns: of a writer, or the keys of the
    # first Hash record. The same rules hold in metacrunch-xlsx.
    class Columns

      PLURALS = {Hash => "Hashes", Array => "Arrays"}.freeze

      # "a Time", "an Array": the class of object with its article.
      def self.described(object)
        name = object.class.name
        "#{name.match?(/\A[AEIOU]/) ? "an" : "a"} #{name}"
      end

      # columns: nil, an Array of unique, non-empty Strings (keys, also the
      # header), or a Hash of header => key.
      def initialize(columns)
        @names, @keys = parse(columns)
        @given = !@keys.nil?
        @kind = nil
      end

      # The header names, or nil while they are not known.
      attr_reader :names

      def known? = !@names.nil?

      # The values of record in column order. Learns the columns from the
      # first Hash record when none were given.
      def row(record, ctx)
        kind = record_kind(record, ctx)
        kind == Hash ? hash_row(record, ctx) : array_row(record, ctx)
      end

      private

      def parse(columns)
        case columns
        when nil then [nil, nil]
        when Array then [check_names(columns), columns]
        when Hash then [check_names(columns.keys), check_keys(columns.values)]
        else raise ArgumentError, "columns must be nil, an Array or a Hash, got #{columns.inspect}"
        end
      end

      def check_names(names)
        unless names.all? { it.is_a?(String) && !it.empty? }
          raise ArgumentError, "column names must be non-empty Strings, got #{names.inspect}"
        end
        raise ArgumentError, "columns must not be empty" if names.empty?

        duplicate = names.find { names.count(it) > 1 }
        raise ArgumentError, "the column #{duplicate.inspect} is named twice" if duplicate

        names
      end

      def check_keys(keys)
        return keys if keys.all? { it.is_a?(String) && !it.empty? }

        raise ArgumentError, "column keys must be non-empty Strings, got #{keys.inspect}"
      end

      # Hash or Array; the first record decides for the run.
      def record_kind(record, ctx)
        kind = [Hash, Array].find { record.is_a?(it) }
        unless kind
          raise Metacrunch::Error, "record at position #{ctx.position} is #{Columns.described(record)}, " \
                                   "not a Hash or an Array"
        end
        @kind ||= kind
        return kind if kind == @kind

        raise Metacrunch::Error, "record at position #{ctx.position} is #{Columns.described(record)}, the records " \
                                 "before it are #{PLURALS[@kind]}; write either Hashes or Arrays"
      end

      def hash_row(record, ctx)
        unless @keys
          @keys = record.keys
          @names = @keys.map(&:to_s)
        end
        check_new_keys(record, ctx) unless @given
        @keys.map { record[it] }
      end

      def check_new_keys(record, ctx)
        return if record.size <= @keys.size && record.each_key.all? { @keys.include?(it) }

        key = record.each_key.find { !@keys.include?(it) }
        raise Metacrunch::Error, "record at position #{ctx.position} has the key #{key.inspect}, which the first " \
                                 "record does not have; name the columns with columns:"
      end

      def array_row(record, ctx)
        return record unless @keys && record.size > @keys.size

        raise Metacrunch::Error, "record at position #{ctx.position} has #{record.size} values for " \
                                 "#{@keys.size} columns"
      end

    end
  end
end
