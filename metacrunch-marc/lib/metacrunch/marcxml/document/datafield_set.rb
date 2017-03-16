module Metacrunch
  module Marcxml
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

        # @return [Metacrunch::Marcxml::Document::SubfieldSet]
        def subfields(code = nil)
          subfields = @datafields.map do |datafield|
            datafield.subfields(code).to_a
          end.flatten(1)

          Metacrunch::Marcxml::Document::SubfieldSet.new(subfields)
        end

      end
    end
  end
end
