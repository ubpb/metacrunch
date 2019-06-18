module Metacrunch
  module Marcxml
    class Document
      class SubfieldSet
        include Enumerable

        def initialize(subfields)
          @subfields = subfields || []
        end

        def each(&block)
          @subfields.each(&block)
        end

        def to_a
          @subfields
        end

        def empty?
          @subfields.empty?
        end

        def present?
          !empty?
        end

        def values
          @subfields.map{ |subfield| subfield.value }
        end

      end
    end
  end
end
