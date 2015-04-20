module Metacrunch
  module Mab2
    class Document
      class DataField
        class SubField

          attr_reader :name
          attr_reader :value

          def initialize(name, value)
            raise ArgumentError, "required SubField#name not given" if name.nil?

            @name  = name
            @value = value
          end

        end
      end
    end
  end
end

