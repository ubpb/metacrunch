module Metacrunch
  module Mab2
    class Document
      class Datafield
        class Subfield
          class Set
            include Enumerable

            def initialize(subfields = [])
              @subfields = subfields
            end

            def each(&block)
              @subfields.each(&block)
            end

            def <<(subfield)
              @subfields << subfield
            end

            def concat(subfield_set)
              @subfields.concat(subfield_set.to_a)
            end

            def to_a
              @subfields
            end

            def values
              @subfields.map{ |subfield| subfield.value }
            end

          end
        end
      end
    end
  end
end
