module Metacrunch
  module Mab2
    class Document
      class Datafield
        class Set
          include Enumerable

          # @return [Array<Metacrunch::Mab2::Document::Datafield>]
          attr_reader :datafields

          def initialize(datafields = [])
            @datafields = datafields
          end

          def each(&block)
            @datafields.each(&block)
          end

          def <<(datafield)
            @datafields << datafield
          end

          def concat(datafield_set)
            @datafields.concat(datafield_set.to_a)
          end

          def to_a
            @datafields
          end

          def filter(ind1: nil, ind2: nil)
            if ind1 || ind2
              self.class.new(self.select{ |datafield| datafield.matches?(ind1: ind1, ind2: ind2) })
            else
              self
            end
          end

           # @return [Metacrunch::Mab2::Document::Datafield::Subfield::Set]
          def subfields(name)
            set = Subfield::Set.new

            @datafields.each do |datafield|
              set.concat(datafield.subfields(name))
            end

            set
          end

        end
      end
    end
  end
end
