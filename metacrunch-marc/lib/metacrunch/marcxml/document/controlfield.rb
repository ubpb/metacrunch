module Metacrunch
  module Marcxml
    class Document
      class Controlfield

        attr_accessor :tag
        attr_accessor :value

        def initialize(tag = nil, value = nil)
          @tag = tag
          @value = value
        end

      end
    end
  end
end
