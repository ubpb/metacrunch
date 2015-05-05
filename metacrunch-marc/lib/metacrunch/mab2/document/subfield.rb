module Metacrunch
  module Mab2
    class Document
      class Datafield
        class Subfield

          attr_reader :code
          attr_reader :value

          def initialize(code, value)
            raise ArgumentError, "required Subfield#code not given" if code.nil?

            @code  = code
            @value = value
          end

        end
      end
    end
  end
end

