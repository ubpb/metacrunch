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

        end
      end
    end
  end
end

