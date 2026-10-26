# frozen_string_literal: true

module Metacrunch
  module Marc
    module Iso2709
      # Writes a Record as ISO 2709 (Record#to_iso2709): leader, directory,
      # the fields in record order, the record terminator. Lengths and starts
      # count UTF-8 bytes. The leader gets the record length, "a" at 09
      # (UTF-8), "22" at 10-11, the base address and "450" at 20-22; the
      # other positions are copied. Internal.
      module Serializer

        # The leader of a record without one, before the computed positions.
        LEADER = "00000    a2200000   4500"
        MAX_FIELD = 9_999
        MAX_RECORD = 99_999
        OVERSIZE = [:error, :allow].freeze
        ANYWAY = "(oversize: :allow writes it anyway)"
        SEPARATORS = FIELD_TERMINATOR + SUBFIELD_DELIMITER

        module_function

        # Values are appended as they are and checked all at once; only if
        # that fails, value by value, to name the place.
        def record(record, oversize:)
          unless OVERSIZE.include?(oversize)
            raise ArgumentError, "oversize must be :error or :allow, got #{oversize.inspect}"
          end

          leader = leader(record.leader)
          directory = String.new(encoding: Encoding::UTF_8)
          data = String.new(encoding: Encoding::UTF_8)
          separators = 0
          record.fields.each do |field|
            start = data.bytesize
            tag = tag(field.tag)
            separators += field.is_a?(DataField) ? data_field(data, field) : control_field(data, field)
            length = data.bytesize - start
            check_field_size(tag, length, oversize)
            directory << tag << number(length, 4) << number(start, 5)
          end
          locate(record) unless clean?(directory, data, separators)
          # The directory ends with a field terminator, the record with a
          # record terminator.
          base = LEADER_LENGTH + directory.bytesize + 1
          size = base + data.bytesize + 1
          check_record_size(size, oversize)
          leader[0, 5] = number(size, 5)
          leader[9] = "a"
          leader[10, 2] = "22"
          leader[12, 5] = number(base, 5)
          leader[20, 3] = "450"
          leader << directory << FIELD_TERMINATOR << data << RECORD_TERMINATOR
        end

        # A copy of the leader to fill in.
        def leader(leader)
          return LEADER.dup if leader.nil?

          string = Values.serializable(leader) { "leader" }
          return string.dup if string.bytesize == LEADER_LENGTH && string.ascii_only?

          raise SerializeError, "leader: an ISO 2709 leader has 24 ASCII characters, got #{string.inspect}"
        end

        def tag(tag)
          return tag if tag.is_a?(String) && tag.bytesize == 3 && tag.ascii_only?

          string = Values.serializable(tag) { Values.location(tag) }
          return string if string.bytesize == 3 && string.ascii_only?

          raise SerializeError, "#{Values.location(tag)}: an ISO 2709 tag has 3 ASCII characters"
        end

        # Appends the field; returns the number of separators appended.
        def control_field(data, field)
          data << text(field.value) { Values.location(field.tag) } << FIELD_TERMINATOR
          1
        end

        # Appends the field; returns the number of separators appended.
        def data_field(data, field)
          subfields = field.subfields
          if subfields.empty?
            raise SerializeError, "#{Values.location(field.tag)}: an ISO 2709 data field needs a subfield; " \
                                  "without one it would be read back as a control field"
          end

          data << character(field.ind1, "indicator") { Values.location(field.tag) }
          data << character(field.ind2, "indicator") { Values.location(field.tag) }
          subfields.each do |subfield|
            code = character(subfield.code, "subfield code") { Values.location(field.tag, subfield.code) }
            data << SUBFIELD_DELIMITER << code << text(subfield.value) { Values.location(field.tag, subfield.code) }
          end
          data << FIELD_TERMINATOR
          subfields.size + 1
        end

        # A UTF-8 String as it is (clean? checks it); others through Values.
        def text(value, &)
          return value if value.is_a?(String) && value.encoding == Encoding::UTF_8

          Values.serializable(value, &)
        end

        # An indicator or a code: one ASCII character.
        def character(value, name, &)
          return value if value.is_a?(String) && value.bytesize == 1 && value.ascii_only?

          string = Values.serializable(value, &)
          return string if string.bytesize == 1 && string.ascii_only?

          raise SerializeError, "#{yield}: an ISO 2709 #{name} is 1 ASCII character, got #{string.inspect}"
        end

        # Whether tags and data keep to the common rule: data with exactly the
        # separators appended, and none of the forbidden characters.
        def clean?(directory, data, separators)
          !directory.match?(Values::CONTROL) && data.valid_encoding? && !data.match?(FORBIDDEN) &&
            data.count(SEPARATORS) == separators &&
            (data.ascii_only? || Values::NONCHARACTERS.none? { data.include?(it) })
        end

        # Raises for the first tag, indicator, code or value that breaks the
        # common rule.
        def locate(record)
          record.fields.each do |field|
            Values.serializable(field.tag) { Values.location(field.tag) }
            next Values.serializable(field.value) { Values.location(field.tag) } if field.is_a?(ControlField)

            Values.serializable(field.ind1) { Values.location(field.tag) }
            Values.serializable(field.ind2) { Values.location(field.tag) }
            field.subfields.each do |subfield|
              Values.serializable(subfield.code) { Values.location(field.tag, subfield.code) }
              Values.serializable(subfield.value) { Values.location(field.tag, subfield.code) }
            end
          end
        end

        def check_field_size(tag, length, oversize)
          return if length <= MAX_FIELD || oversize == :allow

          raise SerializeError, "field #{tag} has #{length} bytes, ISO 2709 allows #{MAX_FIELD} #{ANYWAY}"
        end

        def check_record_size(size, oversize)
          return if size <= MAX_RECORD || oversize == :allow

          raise SerializeError, "the record has #{size} bytes, ISO 2709 allows #{MAX_RECORD} #{ANYWAY}"
        end

        # value with leading zeros, or all nines if it does not fit.
        def number(value, digits)
          string = value.to_s
          string.bytesize > digits ? "9" * digits : string.rjust(digits, "0")
        end

      end
    end
  end
end
