# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # Settings and mappings of an index: a Hash, or the path of a JSON file
    # that may have comments and trailing commas.
    module Definition

      module_function

      # The Hash of value (with String keys), or nil for nil. what names the
      # value in errors ("settings", "mappings").
      def load(value, what)
        case value
        when nil then nil
        when Hash then stringify(value)
        when String, Pathname then read(value.to_s)
        else raise ArgumentError, "#{what} must be a Hash or a path, got #{value.class}"
        end
      end

      # Settings with flat "index." keys, as Elasticsearch stores them:
      # {"number_of_replicas" => 0, "analysis" => {"analyzer" => {...}}}
      # becomes {"index.number_of_replicas" => 0, "index.analysis.analyzer..." => ...}.
      # So single keys can be set whatever form the file uses.
      def flat_settings(settings)
        flatten(settings || {}).transform_keys { it.start_with?("index.") ? it : "index.#{it}" }
      end

      def read(path)
        data = JSON.parse(File.read(path), allow_comments: true, allow_trailing_comma: true)
        raise Error, "#{path}: the file must hold a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise Error, "#{path}: #{e.message}"
      rescue SystemCallError => e
        raise Error, "#{path}: #{e.message.sub(/ @ \w+/, "").sub(/ - #{Regexp.escape(path)}\z/, "")}"
      end

      def stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { stringify(it) }
        else value
        end
      end

      def flatten(hash, prefix = nil)
        hash.each_with_object({}) do |(key, value), flat|
          name = prefix ? "#{prefix}.#{key}" : key.to_s
          value.is_a?(Hash) ? flat.merge!(flatten(value, name)) : flat[name] = value
        end
      end

    end
  end
end
