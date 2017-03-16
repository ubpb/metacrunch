module Metacrunch
  module Mab2
    class Document
      class Controlfield

        attr_reader :tag

        def initialize(tag, values = [])
          @tag = tag
          self.values = values
        end

        #
        # Setter for the control field values. Values can be given as String or
        # as an Array.
        #
        # @param [String, Array<String>] values for the control field as a string or
        #   array of strings.
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
            else []
            end
        end

        #
        # @return [Array<String>]
        #
        def values
          @values
        end

        #
        # @param [int] index
        # @return [String] value at given index
        #
        def value(index)
          @values.at(index)
        end
        alias_method :at, :value
        alias_method :[], :value

      private

        def string2values(string)
          string.chars.to_a.map{ |e| (e=="|") ? nil : e }
        end

        def array2values(array)
          array.map do |v|
            if v.present?
              v = v.to_s
              raise ArgumentError, "invalid value of controlfield #{tag}: #{array}" if v.length > 1
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
