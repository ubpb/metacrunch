module Metacrunch
  module Mab2
    class Document
      class DataField
        class SubField
          class Set
            include Enumerable

            # @return [Array<Metacrunch::Mab2::Document::SubField>]
            attr_reader :sub_fields

            def initialize(sub_fields = [])
              @sub_fields = sub_fields
            end

            def each(&block)
              @sub_fields.each(&block)
            end

            def <<(sub_field)
              @sub_fields << sub_field
            end

            def concat(sub_field_set)
              @sub_fields.concat(sub_field_set.to_a)
            end

            def to_a
              @sub_fields
            end

            def values
              @sub_fields.map{ |sub_field| sub_field.value }
            end

          end
        end
      end
    end
  end
end
