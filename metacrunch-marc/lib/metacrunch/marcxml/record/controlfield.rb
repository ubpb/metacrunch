module Metacrunch
  module Marcxml
    class Record
      class Controlfield

        attr_accessor :tag
        attr_accessor :value

        def initialize(tag = nil, value = nil)
          @tag = tag
          @value = value
        end

        def to_h
          {tag => value}
        end

      end
    end
  end
end
