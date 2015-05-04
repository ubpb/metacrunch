module Metacrunch
  module Mab2
    class Document
      class DataField
        class Set
          include Enumerable

          # @return [Array<Metacrunch::Mab2::Document::DataField>]
          attr_reader :data_fields

          def initialize(data_fields = [])
            @data_fields = data_fields
          end

          def each(&block)
            @data_fields.each(&block)
          end

          def <<(data_field)
            @data_fields << data_field
          end

          def concat(data_field_set)
            @data_fields.concat(data_field_set.to_a)
          end

          def to_a
            @data_fields
          end

          def filter(ind1: nil, ind2: nil)
            if ind1 || ind2
              self.class.new(self.select{ |data_field| data_field.matches?(ind1: ind1, ind2: ind2) })
            else
              self
            end
          end

           # @return [Metacrunch::Mab2::Document::DataField::SubField::Set]
          def sub_fields(name)
            set = SubField::Set.new

            @data_fields.each do |data_field|
              set.concat(data_field.sub_fields(name))
            end

            set
          end

        end
      end
    end
  end
end
