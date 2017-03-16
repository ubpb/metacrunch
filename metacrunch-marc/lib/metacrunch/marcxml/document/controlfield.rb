module Metacrunch
  module Marcxml
    class Document
      class Controlfield

        attr_reader :tag
        attr_reader :value

        def initialize(tag, value)
          @tag = tag
          @value = value
        end

      end
    end
  end
end
