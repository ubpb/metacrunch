# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The worksheet's XML, written row by row to a sink (a ZIP entry). The
    # start waits for the columns, since column widths come before the rows.
    # Internal.
    class Sheet

      MAX_ROWS = 1_048_576
      MAX_COLUMNS = 16_384
      BOLD = 1
      HEAD = <<~XML.delete("\n").freeze
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
         xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      XML
      FROZEN = '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" ' \
               'state="frozen"/></sheetView></sheetViews>'

      # The rows so far, the header included, and the most values in a row.
      attr_reader :rows, :columns

      def initialize(sink)
        @sink = sink
        @rows = 0
        @columns = 0
        @header = false
        @started = false
      end

      def started? = @started

      # Writes the start of the worksheet. header: the names of a header row,
      # or nil. widths: widths by position (nil for Excel's default), or nil.
      # Raises Cells::Unwritable for a header that cannot be written, and
      # then writes nothing.
      def start(header, widths)
        header = nil if header && header.empty?
        first = header && row_xml(header, 1, BOLD)
        xml = +HEAD
        xml << FROZEN if header
        xml << cols(widths) if widths&.any?
        xml << "<sheetData>"
        xml << first if first
        @sink << xml
        @started = true
        count(header) if header
        @header = !header.nil?
      end

      # Writes a row of values. Raises Cells::Unwritable (with the column's
      # index for a value) for a row that cannot be written, and then writes
      # nothing.
      def row(values)
        @sink << row_xml(values, @rows + 1, nil)
        count(values)
      end

      # Ends the worksheet: the autofilter covers the header and all rows.
      def finish
        filter = %(<autoFilter ref="#{range}"/>) if @header
        @sink << "</sheetData>#{filter}</worksheet>"
      end

      # The range of the header and all rows ("A1:C10"); nil without a
      # header.
      def range
        return unless @header

        "A1:#{Cells.column(@columns - 1)}#{@rows}"
      end

      # The range in Excel's absolute form ("$A$1:$C$10").
      def absolute_range = range&.gsub(/([A-Z]+)(\d+)/, '$\1$\2')

      private

      def count(values)
        @rows += 1
        @columns = values.size if values.size > @columns
      end

      def cols(widths)
        entries = widths.each_with_index.filter_map do |width, index|
          %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>) if width
        end
        "<cols>#{entries.join}</cols>"
      end

      def row_xml(values, number, style)
        raise Cells::Unwritable, "would be row #{number}; Excel has #{MAX_ROWS} rows" if number > MAX_ROWS
        if values.size > MAX_COLUMNS
          raise Cells::Unwritable, "has #{values.size} values; Excel has #{MAX_COLUMNS} columns"
        end

        xml = %(<row r="#{number}">)
        values.each_with_index do |value, index|
          cell = Cells.cell(value, "#{Cells.column(index)}#{number}", style)
          xml << cell if cell
        rescue Cells::Unwritable => e
          raise Cells::Unwritable.new(e.message, index:)
        end
        xml << "</row>"
      end

    end
  end
end
