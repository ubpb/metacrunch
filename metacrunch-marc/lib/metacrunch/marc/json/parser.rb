# frozen_string_literal: true

module Metacrunch
  module Marc
    module Json
      # Builds Records from MARC-in-JSON: lines of JSON (Json.parse, .each)
      # and Hashes as Record#to_h returns them (Record.from_h). The shape is
      # strict: keys are Strings, a field has one key (its tag), a data field
      # has "ind1", "ind2" (missing or nil is " ") and "subfields". Every
      # problem raises ParseError with the path to it, e.g. "fields[3] (245)
      # subfields[0]: a value must be a String, got 12". Internal.
      class Parser

        RECORD_KEYS = ["leader", "fields"].freeze
        DATA_FIELD_KEYS = ["ind1", "ind2", "subfields"].freeze
        ONE_PER_LINE = "MARC-in-JSON has one record per line; jq -c . in.json > out.jsonl converts pretty-printed JSON"

        # The record of one JSON object in line; a byte order mark at its
        # start is skipped.
        def self.line(line, normalize:)
          bytes = line.b
          bytes.delete_prefix!(BOM)
          raise ParseError, "no record found" if bytes.strip.empty?

          # JSON takes invalid UTF-8 inside strings, so it is checked first.
          text = bytes.force_encoding(Encoding::UTF_8)
          raise ParseError, "invalid UTF-8" unless text.valid_encoding?

          new(normalize).record(json(text))
        end

        # The Hash of text. Duplicate keys raise, also with the json 2 that comes
        # with Ruby 4.0, which keeps the last one by default. A line that is not
        # a whole object, as in a pretty-printed file, gets a hint.
        def self.json(text)
          value = JSON.parse(text, allow_duplicate_key: false)
          return value if value.is_a?(Hash)

          raise ParseError, "a record must be a JSON object, got #{short(value)}"
        rescue JSON::ParserError => e
          stripped = text.strip
          whole = stripped.start_with?("{") && stripped.end_with?("}")
          raise ParseError, whole ? e.message : "#{e.message} (#{ONE_PER_LINE})"
        end

        # value for a message, cut after 40 characters.
        def self.short(value)
          text = value.inspect
          text.length > 40 ? "#{text[0, 37]}..." : text
        end

        def initialize(normalize)
          @normalize = normalize
        end

        def record(hash)
          raise ParseError, "a record must be a Hash, got #{short(hash)}" unless hash.is_a?(Hash)

          unknown = hash.each_key.find { !RECORD_KEYS.include?(it) }
          raise ParseError, "unknown key #{unknown.inspect}; a record has \"leader\" and \"fields\"" if unknown

          fields = hash.fetch("fields") { raise ParseError, "a record needs \"fields\"" }
          raise ParseError, "fields: must be an Array, got #{short(fields)}" unless fields.is_a?(Array)

          leader = hash["leader"]
          leader = value(leader, "leader") unless leader.nil?
          Record.new(leader:, fields: fields.each_with_index.map { |field, index| field(field, "fields[#{index}]") })
        end

        private

        def field(field, path)
          unless field.is_a?(Hash) && field.size == 1
            raise ParseError, "#{path}: a field must be an object with one key, its tag, got #{short(field)}"
          end

          tag, content = field.first
          tag = name(tag, path, "a tag")
          path = "#{path} (#{Values.readable(tag)})"
          case content
          when String then ControlField.new(tag, value(content, path))
          when Hash then data_field(tag, content, path)
          else
            raise ParseError, "#{path}: a field must be a String (a control field) or an object (a data field), " \
                              "got #{short(content)}"
          end
        end

        def data_field(tag, hash, path)
          unknown = hash.each_key.find { !DATA_FIELD_KEYS.include?(it) }
          if unknown
            raise ParseError, "#{path}: unknown key #{unknown.inspect}; a data field has \"ind1\", \"ind2\" and " \
                              "\"subfields\""
          end

          subfields = hash.fetch("subfields") { raise ParseError, "#{path}: a data field needs \"subfields\"" }
          raise ParseError, "#{path} subfields: must be an Array, got #{short(subfields)}" unless subfields.is_a?(Array)

          subfields = subfields.each_with_index.map do |subfield, index|
            subfield(subfield, "#{path} subfields[#{index}]")
          end
          DataField.new(tag, indicator(hash["ind1"], "#{path} ind1"), indicator(hash["ind2"], "#{path} ind2"),
                        subfields)
        end

        def indicator(value, path) = value.nil? ? DataField::BLANK : name(value, path, "an indicator")

        def subfield(subfield, path)
          unless subfield.is_a?(Hash) && subfield.size == 1
            raise ParseError, "#{path}: a subfield must be an object with one key, its code, got #{short(subfield)}"
          end

          code, content = subfield.first
          Subfield.new(name(code, path, "a code"), value(content, path))
        end

        # A tag, an indicator or a code: a String under the common rule.
        def name(name, path, kind)
          raise ParseError, "#{path}: #{kind} must be a String, got #{short(name)}" unless name.is_a?(String)

          Values.parsed(name, nil) { path }
        end

        # A leader or a value: a String under the common rule, normalized
        # with normalize: :nfc.
        def value(value, path)
          raise ParseError, "#{path}: a value must be a String, got #{short(value)}" unless value.is_a?(String)

          Values.parsed(value, @normalize) { path }
        end

        def short(value) = Parser.short(value)

      end
    end
  end
end
