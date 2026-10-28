# frozen_string_literal: true

module Metacrunch
  module Redis
    # How records become the values Redis stores, and back. :json generates
    # and parses JSON, so records cross Redis as they are; :string writes and
    # reads Strings as they are.
    module Format

      FORMATS = [:json, :string].freeze

      module_function

      def check!(value)
        return value if FORMATS.include?(value)

        raise ArgumentError, "format must be :json or :string, got #{value.inspect}"
      end

      # The value of a record; raises Error for a record the format cannot
      # write.
      def encode(format, record)
        return JSON.generate(record, strict: true) if format == :json
        return record if record.is_a?(String)

        raise Error, "record is a #{record.class}, not a String (format: :string)"
      rescue JSON::GeneratorError => e
        raise Error, "record is not JSON (#{record.class}): #{e.message}"
      end

      # The record of a value. A value that is not valid JSON, or not valid
      # UTF-8, becomes an InvalidRecord with raw, so the job's failure policy
      # decides.
      def decode(format, value, raw: value)
        return value if format == :string

        text = value.encoding == Encoding::UTF_8 ? value : value.dup.force_encoding(Encoding::UTF_8)
        return InvalidRecord.new(raw:, error: JSON::ParserError.new("invalid UTF-8")) unless text.valid_encoding?

        JSON.parse(text, allow_duplicate_key: false)
      rescue JSON::ParserError => e
        InvalidRecord.new(raw:, error: e)
      end

    end
  end
end
