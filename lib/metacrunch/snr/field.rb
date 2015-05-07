module Metacrunch
  class SNR
    class Section
      class Field

        attr_reader   :name
        attr_accessor :value

        def initialize(name, value)
          raise ArgumentError, "required Field#name not given" if name.nil?

          @name  = name
          @value = value
        end

        # ------------------------------------------------------------------------------
        # Serialization
        # ------------------------------------------------------------------------------

        def to_xml(builder)
          builder.tag!(self.name) do
            value.to_xml(builder: builder, skip_instruct: true)
          end
        end

      end
    end
  end
end
