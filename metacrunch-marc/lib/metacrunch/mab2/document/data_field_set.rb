module Metacrunch
  module Mab2
    class Document
      class DataField
        class Set < Delegator

          # @return [Array<Metacrunch::Mab2::Document::DataField>]
          attr_reader :data_fields

          def initialize(data_fields = [])
            @data_fields = data_fields
          end

          def __getobj__
            @data_fields
          end

          def filter(ind1: nil, ind2: nil)
            self.class.new(self.select{ |data_field| data_field.matches?(ind1: ind1, ind2: ind2) })
          end

           # @return [Array<Metacrunch::Mab2::Document::DataField::SubField::Set>]
          def sub_fields(name)
            set = SubField::Set.new

            self.each do |data_field|
              set.concat(data_field.sub_fields(name))
            end

            set
          end

        end
      end
    end
  end
end
