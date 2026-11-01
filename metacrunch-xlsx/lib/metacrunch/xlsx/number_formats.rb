# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # Tells by its number format whether a number is a date, a date and
    # time, a time of day, a duration or a plain number. Internal.
    module NumberFormats

      # Built-in formats by id; the others are numbers. 27-36 and 50-58 are
      # the East Asian date formats.
      BUILT_IN = [
        *[14, 15, 16, 17, *27..36, *50..58].map { [it, :date] },
        [22, :date_time], *[18, 19, 20, 21, 45, 47].map { [it, :time] }, [46, :duration]
      ].to_h.freeze

      # Parts of a code that show no date or time: quoted text, escaped
      # characters, the space of _x, the fill of *x, "General", the
      # exponent of scientific formats.
      LITERALS = /"[^"]*"|\\.|_.|\*.|general|e[+-]/i
      ELAPSED = /\[(?:h+|m+|s+)\]/i
      BRACKETS = /\[[^\]]*\]/
      MERIDIEM = %r{am/pm|a/p}i
      LETTERS = /y+|m+|d+|h+|s+/

      module_function

      # :number, :date, :date_time, :time or :duration for the format id;
      # code: its code from styles.xml, which decides over the id.
      def kind(id, code = nil)
        return BUILT_IN.fetch(id, :number) unless code

        section = code.gsub(LITERALS, "").split(";").first.to_s
        return :duration if section.match?(ELAPSED)

        section = section.gsub(BRACKETS, "")
        time = section.match?(MERIDIEM)
        tokens = section.gsub(MERIDIEM, "").downcase.scan(LETTERS)
        date = false
        tokens.each_with_index do |token, index|
          if minutes?(tokens, index) || token.start_with?("h", "s") then time = true
          else date = true
          end
        end
        return :date_time if date && time
        return :date if date

        time ? :time : :number
      end

      # An m is minutes right after h or right before s, else the month.
      def minutes?(tokens, index)
        return false unless tokens[index].start_with?("m")

        (index.positive? && tokens[index - 1].start_with?("h")) || tokens[index + 1]&.start_with?("s") || false
      end

    end
  end
end
