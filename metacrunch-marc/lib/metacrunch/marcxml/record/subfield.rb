module Metacrunch
  module Marcxml
    class Record
      class Subfield

        attr_accessor :code
        attr_accessor :value

        def initialize(code = nil, value = nil)
          @code  = code
          @value = value
        end

        def to_h
          {code => value}
        end

      end
    end
  end
end
