# frozen_string_literal: true

module Metacrunch
  module Marc
    module Json
      # Writes a Record as one line of MARC-in-JSON: JSON.generate of to_h
      # and "\n", with every String checked by the common rule first, so a
      # character that XML cannot represent raises although JSON could
      # escape it. The type is dropped. Internal.
      module Serializer

        module_function

        def record(record)
          hash = {}
          hash["leader"] = Values.serializable(record.leader) { "leader" } if record.leader
          hash["fields"] = record.fields.map { field(it) }
          "#{JSON.generate(hash)}\n"
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
