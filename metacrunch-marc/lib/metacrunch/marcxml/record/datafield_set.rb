module Metacrunch
  module Marcxml
    class Record
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

        # @return [Metacrunch::Marcxml::Record::SubfieldSet]
        def subfields(code = nil, flatten: true)
          if flatten
            subfields = @datafields.map do |datafield|
              datafield.subfields(code)
            end.flatten(1)

            Metacrunch::Marcxml::Record::SubfieldSet.new(subfields)
          else
            @datafields.map do |datafield|
              Metacrunch::Marcxml::Record::SubfieldSet.new(datafield.subfields(code))
            end
          end
        end

      end
    end
  end
end
