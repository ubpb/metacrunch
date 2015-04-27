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

      end
    end
  end
end
