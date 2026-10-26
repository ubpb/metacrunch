# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # Elasticsearch's rules for the names of indices and aliases, checked
    # before a request, so a typo does not create an index or an alias.
    module Names

      # Characters Elasticsearch refuses in names (the colon since 7.0).
      INVALID = %r{[\\/*?"<>|,#: ]}

      module_function

      # Returns name, or raises ArgumentError saying what is wrong with it.
      # what: "index", "alias".
      def check(name, what)
        problem = problem(name)
        return name unless problem

        raise ArgumentError, "#{what} #{name.inspect} is not a valid name: #{problem}"
      end

      # What a reader or a search reads: a name, alias or pattern, or an
      # Array of them. Returns the Array; raises ArgumentError otherwise.
      def targets(value)
        list = Array(value)
        return list if !list.empty? && list.all? { it.is_a?(String) && !it.empty? }

        raise ArgumentError, "index must be a name, alias or pattern, or an Array of them, got #{value.inspect}"
      end

      def problem(name)
        if !name.is_a?(String) then "it must be a String"
        elsif name.empty? then "it is empty"
        elsif name.match?(/\p{Upper}/) then "it has uppercase letters"
        elsif name.match?(INVALID) then "it contains #{name[INVALID].inspect}"
        elsif name.start_with?("-", "_", "+") then "it starts with #{name[0]}"
        elsif [".", ".."].include?(name) then "it is #{name}"
        elsif name.bytesize > 255 then "it is longer than 255 bytes"
        end
      end

    end
  end
end
