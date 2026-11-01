# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The rows of a worksheet as typed values, one row at a time: text as
    # String, numbers as Integer or Float, booleans, errors as their text,
    # dates as ISO Strings (see Dates). The empty text counts as no value.
    # Internal.
    class Rows

      LAST_ROW = 1_048_576
      LAST_COLUMN = 16_384
      PREFIX = Xml::PREFIX
      CELL = %r{<#{PREFIX}c(?=[\s>/])((?:[^>"']|"[^"]*"|'[^']*')*?)(?:/>|>(.*?)</#{PREFIX}c\s*>)}m
      VALUE = %r{<#{PREFIX}v(?:\s[^>]*)?>(.*?)</#{PREFIX}v\s*>}m
      INLINE = %r{<#{PREFIX}is(?=[\s>/]).*?</#{PREFIX}is\s*>}m
      REFERENCE = /\A([A-Z]{1,3})\d*\z/
      INTEGER = /\A-?\d+\z/
      # An ISO 8601 date, date and time, or time, as cells of type d hold.
      ISO = /\A(\d{4}-\d{2}-\d{2})?(?:T?(\d{2}:\d{2}:\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?\z/
      MIDNIGHT = "00:00:00"
      # Below this, an integral Float is exact and becomes an Integer.
      EXACT = 1e15

      # The cell that cannot be read. Internal.
      class Defect < StandardError; end

      def initialize(workbook, sheet, name)
        @workbook = workbook
        @sheet = sheet
        @name = name
        @kinds = workbook.kinds
        @date1904 = workbook.date1904?
      end

      # Yields the Excel row number, the values from column A to the last
      # one with a value (nil in gaps) and nil, or a ParseError for the
      # first cell that cannot be read (its XML text stands in values).
      # Rows without a value are skipped.
      def each
        previous = 0
        Xml.each_element(@workbook.stream(@sheet.part), "row", part: @sheet.part, name: @name) do |row|
          number = row_number(Xml.attributes(row)["r"], previous)
          previous = number
          values, defect = cells(row, number)
          yield number, values, defect if defect || !values.empty?
        end
      end

      private

      def row_number(reference, previous)
        number = reference ? Integer(reference, 10, exception: false) : previous + 1
        raise broken(%(row reference #{reference.inspect})) unless number
        raise broken("row #{number} after row #{previous}") if number <= previous
        raise broken("row #{number} beyond Excel's last row") if number > LAST_ROW

        number
      end

      def cells(row, number)
        values = []
        defect = nil
        column = -1
        row.scan(CELL) do |attributes_xml, content|
          match = Regexp.last_match
          attributes = Xml.pairs(attributes_xml)
          column = column(attributes["r"], column, number)
          begin
            value = value(attributes, content.to_s)
          rescue Defect => e
            defect ||= ParseError.new("cell #{Cells.column(column)}#{number}: #{e.message}")
            value = match[0]
          end
          values[column] = value unless value.nil?
        end
        [values, defect]
      end

      # The index of the cell's column; the names in messages are built
      # only for them, as this runs for every cell.
      def column(reference, previous, number)
        index = reference ? reference_index(reference) : previous + 1
        return index if index > previous && index < LAST_COLUMN

        name = "#{Cells.column(index)}#{number}"
        raise broken("cell #{name} beyond Excel's last column") if index >= LAST_COLUMN

        raise broken("cell #{name} after #{Cells.column(previous)}#{number}")
      end

      # The letters of a reference such as "AB12" as an index from 0.
      def reference_index(reference)
        raise broken("cell reference #{reference.inspect}") unless reference.match?(REFERENCE)

        index = 0
        reference.each_byte do |byte|
          break if byte < 65 # a digit

          index = (index * 26) + byte - 64
        end
        index - 1
      end

      # The value of a cell, nil for none; raises Defect.
      def value(attributes, content)
        type = attributes["t"]
        return blank(Xml.text(content[INLINE].to_s)) if type == "inlineStr"

        raw = content[VALUE, 1]
        return if raw.nil?

        case type
        when nil, "n" then number(raw, kind(attributes))
        when "s" then shared_string(raw)
        when "str" then blank(Xml.content(raw))
        when "b" then boolean(raw)
        when "e" then Xml.unescape(raw)
        when "d" then iso_date(Xml.unescape(raw), kind(attributes))
        else raise Defect, "type #{type.inspect}"
        end
      end

      def blank(text) = text.empty? ? nil : text

      # Format 0 is General also when cellXfs is empty.
      def kind(attributes)
        index = attributes["s"].to_i
        @kinds.fetch(index) do
          next :number if index.zero?

          raise Defect, "format #{index}, the styles have #{@kinds.size}"
        end
      end

      def number(raw, kind)
        return if raw.empty?

        number = numeric(raw)
        return number unless [:date, :date_time, :time].include?(kind)

        Dates.iso(number, kind, date1904: @date1904) || number
      end

      def numeric(raw)
        return Integer(raw, 10) if raw.match?(INTEGER)

        float = Float(raw, exception: false)
        raise Defect, "number #{raw.inspect}" unless float&.finite?

        float == float.floor && float.abs < EXACT ? float.to_i : float
      end

      def shared_string(raw)
        strings = @workbook.shared_strings
        index = Integer(raw, 10, exception: false)
        raise Defect, "shared string #{raw}, the table has #{strings.size}" unless index&.between?(0, strings.size - 1)

        blank(strings[index])
      end

      def boolean(raw)
        case raw
        when "1" then true
        when "0" then false
        else raise Defect, "boolean #{raw.inspect}"
        end
      end

      # An ISO cell (type d) in the form its format shows: date, time or
      # both; General shows the date alone at midnight.
      def iso_date(raw, kind)
        match = raw.match(ISO)
        date, time = match&.captures
        raise Defect, "date #{raw.inspect}" unless date || time

        case kind
        when :date then date || raise(Defect, "date #{raw.inspect}")
        when :time then time || MIDNIGHT
        else date_time(date, time, kind)
        end
      end

      def date_time(date, time, kind)
        return time unless date
        return date if kind != :date_time && (time.nil? || time == MIDNIGHT)

        "#{date}T#{time || MIDNIGHT}"
      end

      def broken(reason) = Xlsx.broken(@name, @sheet.part, reason)

    end
  end
end
