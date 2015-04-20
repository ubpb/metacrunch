module Metacrunch
  module Mab2
    class Document
      class DataField
        class SubField
          class Set < Delegator

            # @return [Array<Metacrunch::Mab2::Document::SubField>]
            attr_reader :sub_fields

            def initialize(sub_fields = [])
              @sub_fields = sub_fields
            end

            def __getobj__
              @sub_fields
            end

            def values
              self.map(&:value)
            end

          end
        end
      end
    end
  end
end
