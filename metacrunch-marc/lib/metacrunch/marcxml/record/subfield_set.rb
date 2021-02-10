module Metacrunch
  module Marcxml
    class Record
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

        def values(as_hash: false)
          if as_hash
            @subfields.map{ |subfield| subfield.to_h }
          else
            @subfields.map{ |subfield| subfield.value }
          end
        end

      end
    end
  end
end
