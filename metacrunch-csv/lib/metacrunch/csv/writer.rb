# frozen_string_literal: true

module Metacrunch
  module Csv
    # A metacrunch sink: writes records as CSV rows to what
    # Metacrunch::Output takes (a path, .gz compressed, "-" for stdout or an
    # IO). Columns come from columns: or from the first Hash record.
    class Writer

      def initialize(target, columns: nil, header: true, col_sep: ",", quote_char: '"', encoding: "UTF-8",
                     bom: false)
        @output = Metacrunch::Output.new(target)
        @columns = Columns.new(columns)
        @encoding = Csv.encoding(col_sep, quote_char, encoding)
        @header = flag(:header, header)
        @bom = flag(:bom, bom)
        if @bom && !BOMS.key?(@encoding)
          raise ArgumentError, "bom: true needs UTF-8, UTF-16LE or UTF-16BE, got #{@encoding}"
        end

        @buffer = StringIO.new(+"")
        @csv = ::CSV.new(@buffer, col_sep:, quote_char:, row_sep: "\n")
        @header_written = false
      end

      # The engine closes no sink whose open raised, so open closes the output
      # itself then.
      def open(_context)
        @output.open
        @output.write(BOMS[@encoding]) if @bom
        @output.write(encode(header_line, nil)) if @header && @columns.known?
      rescue StandardError
        close
        raise
      end

      def write(record, ctx)
        @output.write(encode(line(record, ctx), ctx))
      end

      # Builds the rows of a batch and writes them in one piece.
      def write_batch(records, ctxs)
        @output.write(encode(records.zip(ctxs).map { |record, ctx| line(record, ctx) }.join, ctxs.first))
      end

      def close = @output.close

      private

      def flag(name, value)
        return value if [true, false].include?(value)

        raise ArgumentError, "#{name}: must be true or false, got #{value.inspect}"
      end

      def header_line
        @header_written = true
        generate(@columns.names)
      end

      def line(record, ctx)
        values = @columns.row(record, ctx).dup
        values.each_index { |index| values[index] = field(values[index], index, ctx) }
        # A row of one empty field would be a blank line, which readers skip.
        values = [""] if values.empty? || values == [nil]
        return generate(values) unless @header && !@header_written && @columns.known?

        header_line << generate(values)
      end

      # One CSV object writes every row into a buffer that is emptied again.
      def generate(values)
        @csv << values
        line = @buffer.string.dup
        @buffer.truncate(0)
        @buffer.rewind
        line
      end

      def field(value, index, ctx)
        case value
        when String
          return value if value.valid_encoding?

          raise Metacrunch::Error, "#{column(index, ctx)} is not valid #{value.encoding}"
        when nil then nil
        when Integer, Float, true, false then value.to_s
        else
          raise Metacrunch::Error, "#{column(index, ctx)} is #{Columns.described(value)}; turn it into a String in " \
                                   "a step"
        end
      end

      def column(index, ctx)
        names = @columns.names
        "record at position #{ctx.position}: column #{names ? names[index].inspect : index + 1}"
      end

      # Bytes for the output: an IO such as StringIO would otherwise convert
      # text of another encoding back into its own.
      def encode(text, ctx)
        return text if @encoding == Encoding::UTF_8

        text.encode(@encoding).b
      rescue EncodingError => e
        at = ctx ? "record at position #{ctx.position}" : "the header"
        raise Metacrunch::Error, "#{at} has a character #{@encoding} cannot represent (#{e.message})"
      end

    end
  end
end
