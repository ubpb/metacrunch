module Metacrunch
  module Mab2
    class Document
      class Datafield
        class Set
          include Enumerable

          def initialize(datafields = [])
            @datafields = datafields
          end

          def each
            block_given? ? @datafields.each { |_datafield| yield _datafield } : to_enum
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

          def empty?
            @datafields.empty?
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
