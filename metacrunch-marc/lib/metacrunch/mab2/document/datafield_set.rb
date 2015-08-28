module Metacrunch
  module Mab2
    class Document
      class DatafieldSet
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
          self
        end

        def first_value
          subfields.first_value
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
        def subfields(codes = nil)
          set = Metacrunch::Mab2::Document::SubfieldSet.new

          @datafields.each do |datafield|
            if codes.nil?
              set.concat(datafield.subfields)
            else
              [codes].flatten(1).each do |_code|
                set.concat(datafield.subfields(_code))
              end
            end
          end

          set
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
