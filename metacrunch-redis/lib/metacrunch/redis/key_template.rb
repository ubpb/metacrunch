# frozen_string_literal: true

module Metacrunch
  module Redis
    # The key of a record from a template: %{name} stands for the value of
    # the record's field name ("book:%{isbn}"). A template without a
    # placeholder is one key for every record.
    class KeyTemplate

      PLACEHOLDER = /%\{([^}]+)\}/

      def initialize(text)
        @text = text
        # Literal text and field names alternate: "book:", "isbn", "".
        @parts = text.split(PLACEHOLDER)
      end

      # Raises Error for a record that gives no key.
      def key(record)
        return @text if @parts.size == 1
        raise Error, "record is a #{record.class}, not a Hash" unless record.is_a?(Hash)

        @parts.each_with_index.map { |part, index| index.odd? ? value(record, part) : part }.join
      end

      def to_s = @text

      private

      def value(record, name)
        value = record.key?(name) ? record[name] : record[name.to_sym]
        return value.to_s if value.is_a?(Integer) || (value.is_a?(String) && !value.empty?)
        raise Error, "no value for #{name} in the key #{@text}" if value.nil? || value == ""

        raise Error, "#{name} is a #{value.class}; a key takes Strings and Integers"
      end

    end
  end
end
