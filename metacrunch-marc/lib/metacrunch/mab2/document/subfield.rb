module Metacrunch
  module Mab2
    class Document
      class Datafield
        class Subfield

          attr_accessor :code
          attr_accessor :value

          def initialize(code = nil, value = nil)
            @code  = code
            @value = value
          end

          # ------------------------------------------------------------------------------
          # Serialization
          # ------------------------------------------------------------------------------

          def to_xml(builder)
            builder.subfield(code: code) do
              builder.text!(value)
            end
          end

        end
      end
    end
  end
end

