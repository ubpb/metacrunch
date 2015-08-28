require "self_enumerable"

module Metacrunch
  module Mab2
    class Document
      class DatafieldSet
        include SelfEnumerable

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
          self
        end

        def value
          @datafields.find { |_datafield| _datafield.value }.try(:value)
        end
        alias_method :first_value, :value

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
          result = Metacrunch::Mab2::Document::SubfieldSet.new

          @datafields.each do |_datafield|
            result.concat(_datafield.subfields(code))
          end

          result
        end

        # ------------------------------------------------------------------------------
        # Serialization
        # ------------------------------------------------------------------------------

        def to_xml(builder)
          self.each do |_datafield|
            _datafield.to_xml(builder)
          end
        end

      end
    end
  end
end
