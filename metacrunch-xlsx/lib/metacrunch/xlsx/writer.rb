# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # A metacrunch sink: writes records as the rows of one worksheet to what
    # Metacrunch::Output takes (a path, "-" for stdout or an IO), streaming
    # in constant memory. A header row is bold, frozen and filtered. Cells
    # follow the Ruby type: String text, Integer and Float numbers, true and
    # false booleans, nil empty.
    class Writer

      FORBIDDEN = %r{[\[\]:*?/\\]}
      MAX_WIDTH = 255

      def initialize(target, columns: nil, header: true, sheet: "Sheet1", widths: nil)
        @output = Metacrunch::Output.new(target)
        @columns = Columns.new(columns)
        @header = check_header(header)
        @sheet_name = check_sheet(sheet)
        @widths = check_widths(widths)
        @zip = nil
        @sheet = nil
      end

      # The engine closes no sink whose open raised, so open finishes the
      # file itself then.
      def open(_context)
        @output.open
        Xlsx.uninterrupted do
          @zip = ZipKit::Streamer.new(@output)
          Package::STATIC.each { |name, xml| part(name, xml) }
          @sink = Entry.new(@zip, "xl/worksheets/sheet1.xml")
          @sheet = Sheet.new(@sink)
        end
        start if @columns.known?
      rescue StandardError
        close
        raise
      end

      def write(record, ctx)
        values = @columns.row(record, ctx)
        start unless @sheet.started?
        @sheet.row(values)
      rescue Cells::Unwritable => e
        raise Metacrunch::Error, message(e, "record at position #{ctx.position}")
      rescue SignalException => e
        # The reader of a pipe went away (Output raises SIGPIPE once and
        # writes nothing after it): there is no file to finish.
        @broken = true if e.signm == "SIGPIPE"
        raise
      end

      # Writes the rows one by one into the compressed stream, which buffers
      # them.
      def write_batch(records, ctxs)
        records.zip(ctxs).each { |record, ctx| write(record, ctx) }
      end

      # Finishes the file, also after an aborted run, with the rows so far;
      # an interrupt waits until the file is complete.
      def close
        Xlsx.uninterrupted { finish if @zip && @sheet && !@broken }
      ensure
        @zip = nil
        @output.close
      end

      private

      def check_header(header)
        return header if [true, false].include?(header)

        raise ArgumentError, "header: must be true or false, got #{header.inspect}"
      end

      # The name in UTF-8, as the workbook needs it.
      def check_sheet(name)
        utf8 = sheet_utf8(name)
        valid = utf8&.length&.between?(1, 31) && !utf8.match?(FORBIDDEN) && !utf8.match?(Cells::INVALID_XML) &&
                !utf8.start_with?("'") && !utf8.end_with?("'")
        return utf8 if valid

        raise ArgumentError, "sheet: must be 1 to 31 characters without [ ] : * ? / \\ or control characters and not " \
                             "start or end with ', got #{name.inspect}"
      end

      def sheet_utf8(name)
        return unless name.is_a?(String) && name.valid_encoding?

        name.encode(Encoding::UTF_8)
      rescue EncodingError
        nil
      end

      def check_widths(widths)
        values = widths.is_a?(Hash) ? widths.values : widths
        return widths if widths.nil? || (values.is_a?(Array) && values.all? { width?(it) })

        raise ArgumentError, "widths: must be a Hash of column name => width or an Array of widths " \
                             "(numbers above 0 and up to #{MAX_WIDTH}, or nil), got #{widths.inspect}"
      end

      # Integers and finite Floats: XML has no form for a Rational (3/2).
      def width?(value)
        value.nil? || ((value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)) && value.positive? &&
                       value <= MAX_WIDTH)
      end

      def start
        names = @columns.names
        @sheet.start(@header ? names : nil, widths_by_position(names))
      rescue Cells::Unwritable => e
        raise Metacrunch::Error, message(e, "the header row")
      end

      def widths_by_position(names)
        return @widths unless @widths.is_a?(Hash)

        unknown = @widths.keys - names.to_a
        raise Metacrunch::Error, "widths: names columns that do not exist: #{unknown.join(", ")}" if unknown.any?

        names.map { @widths[it] }
      end

      # A sheet that never started (a run aborted before the first row) ends
      # without a header.
      def finish
        @sheet.start(nil, nil) unless @sheet.started?
        @sheet.finish
        @sink.close
        part("xl/workbook.xml", Package.workbook(@sheet_name, @sheet.absolute_range))
        @zip.close
      end

      def part(name, xml)
        entry = Entry.new(@zip, name)
        entry << xml
        entry.close
      end

      def message(error, subject)
        return "#{subject} #{error.message}" if error.index.nil?

        names = @columns.names
        "#{subject}: column #{names ? names[error.index].inspect : error.index + 1} #{error.message}"
      end

    end
  end
end
