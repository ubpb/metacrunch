module Metacrunch
  module Mab2
    class Document
      class DatafieldSet
        include Enumerable

        def initialize(datafields)
          @datafields = datafields || []
        end

        def each(&block)
          @datafields.each(&block)
        end

        def to_a
          @datafields
        end

        def empty?
          @datafields.empty?
        end

        def present?
          !empty?
        end

        # @return [Metacrunch::Mab2::Document::SubfieldSet]
        def subfields(code = nil)
          subfields = @datafields.map do |datafield|
            datafield.subfields(code).to_a
          end.flatten(1)

          Metacrunch::Mab2::Document::SubfieldSet.new(subfields)
        end

      end
    end
  end
end
