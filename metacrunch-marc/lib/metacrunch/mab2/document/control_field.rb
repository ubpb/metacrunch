module Metacrunch
  module Mab2
    class Document
      class ControlField

        # @return [String]
        attr_reader :name

        def initialize(name, values)
          raise ArgumentError, "required ControlField#name not given" if name.blank?
          @name = name.to_s
          self.values = values
        end

        #
        # Setter for the control field values. Values can be given as String or
        # as an Array.
        #
        # @param [String, Array] values for the control field as a String or Array.
        #   In case of String the MAB2 delimiter/placeholder | is respected. In case
        #   of an Array every element is converted into a String. Empty strings are
        #   converted into nil. Array values that are longer than one character will
        #   raise an ArgumentError.
        #
        # @example Add control field using String values
        #   add_control_field("050", "a|b||")
        #
        # @example Add control field using Array
        #   add_control_field("050", ["a", nil, "b", nil, nil])
        #
        def values=(values)
          @values = case values
            when String then string2values(values)
            when Array  then array2values(values)
            when nil    then []
            else
              raise ArgumentError, "expecting a String or Array, but got #{values}"
            end
        end

        #
        # @return [Array<String>]
        #
        def values
          @values || []
        end

        #
        # @param [int] index
        # @return [Array<String>] value at given index
        #
        def at(index)
          @values.at(index)
        end

      private

        def string2values(string)
          string.chars.to_a.map{ |e| (e=="|") ? nil : e }
        end

        def array2values(values)
          values.map do |v|
            if v.present?
              v = v.to_s
              raise ArgumentError, "invalid value of controlfield #{name}: #{values}" if v.length > 1
              v
            else
              nil
            end
          end
        end

      end
    end
  end
end
