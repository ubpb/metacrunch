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
          if value.respond_to?(:to_xml)
            value.to_xml(root: self.name, builder: builder, skip_instruct: true)
          else
            builder.tag!(self.name, self.value)
          end
        end

      end
    end
  end
end
