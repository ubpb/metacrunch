# frozen_string_literal: true

module Metacrunch
  module Marc
    module Json
      # Writes a Record as one line of MARC-in-JSON (Record#to_json), without
      # its line break: JSON.generate of to_h, with every String keeping to
      # the common rule, so a character that XML cannot represent raises
      # although JSON could escape it. The type is dropped. Internal.
      #
      # Checking every String costs more than the JSON. So the line is first
      # written as it is and checked as a whole: JSON writes the forbidden
      # control characters as escapes and the noncharacters as they are, and
      # fails on invalid UTF-8. Only if a check fails, or a value is no
      # String, is the line written again with every String checked, which
      # raises with the place or writes what the escapes only resembled.
      module Serializer

        # The escapes JSON writes for control characters that XML cannot
        # represent; also a backslash before such letters, which costs the
        # second way only.
        ESCAPES = /\\(?:[bf]|u00(?:0[0-8bef]|1\h))/
        BACKSLASH = "\\"

        module_function

        def record(record)
          plain(record) || checked(record)
        end

        # The line, or nil if a value is no String or the line breaks the
        # common rule.
        def plain(record)
          leader = record.leader
          return unless leader.nil? || leader.is_a?(String)

          hash = {}
          hash["leader"] = leader if leader
          hash["fields"] = record.fields.map { plain_field(it) || (return nil) }
          line = JSON.generate(hash)
          line unless escapes?(line) || (!line.ascii_only? && Values::NONCHARACTERS.any? { line.include?(it) })
        rescue JSON::GeneratorError
          nil
        end

        # The regular expression is slow; most lines have no backslash.
        def escapes?(line) = line.include?(BACKSLASH) && line.match?(ESCAPES)

        def plain_field(field)
          tag = field.tag
          if field.is_a?(ControlField)
            value = field.value
            return {tag => value} if value.is_a?(String)

            return
          end
          ind1 = field.ind1
          ind2 = field.ind2
          return unless ind1.is_a?(String) && ind2.is_a?(String)

          subfields = field.subfields.map do |subfield|
            code = subfield.code
            value = subfield.value
            return nil unless code.is_a?(String) && value.is_a?(String)

            {code => value}
          end
          {tag => {"ind1" => ind1, "ind2" => ind2, "subfields" => subfields}}
        end

        # The line with every String checked; raises SerializeError with the
        # place of the first that breaks the common rule.
        def checked(record)
          hash = {}
          hash["leader"] = Values.serializable(record.leader) { "leader" } if record.leader
          hash["fields"] = record.fields.map { field(it) }
          JSON.generate(hash)
        end

        def field(field)
          tag = Values.serializable(field.tag) { Values.location(field.tag) }
          return {tag => Values.serializable(field.value) { Values.location(field.tag) }} if field.is_a?(ControlField)

          subfields = field.subfields.map do |subfield|
            code = Values.serializable(subfield.code) { Values.location(field.tag, subfield.code) }
            {code => Values.serializable(subfield.value) { Values.location(field.tag, subfield.code) }}
          end
          {tag => {"ind1" => Values.serializable(field.ind1) { Values.location(field.tag) },
                   "ind2" => Values.serializable(field.ind2) { Values.location(field.tag) },
                   "subfields" => subfields}}
        end

      end
    end
  end
end
