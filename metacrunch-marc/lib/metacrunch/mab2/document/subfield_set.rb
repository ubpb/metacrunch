require "self_enumerable"

module Metacrunch
  module Mab2
    class Document
      class SubfieldSet
        include SelfEnumerable

        def initialize(subfields = [])
          @subfields = subfields
        end

        def each
          block_given? ? @subfields.each { |_subfield| yield _subfield } : to_enum
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

        def empty?
          @subfields.empty?
        end

        def present?
          !empty?
        end

        def value
          values.find{ |v| v.present? }
        end
        alias_method :first_value, :value

        def values
          @subfields.map{ |subfield| subfield.value }
        end

      end
    end
  end
end
