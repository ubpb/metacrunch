# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # A metacrunch source: reads one worksheet of XLSX workbooks from what
    # Metacrunch::Input reads (paths, "-" for stdin, IOs or an Array of
    # them; gzip is unpacked, tar when unpack: names it) and yields a Hash
    # per row, or an Array with headers: false, as Csv::Reader does. Values
    # are typed as the cells store them; dates are ISO 8601 Strings. A row
    # that does not fit the header, or with a cell that cannot be read, is
    # yielded as Metacrunch::InvalidRecord.
    class Reader

      # The signature of OLE compound files: Excel 97-2003 workbooks, and
      # encrypted workbooks of any version.
      COMPOUND = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b
      # What the reader may unpack around a workbook.
      UNPACK = [:gzip, :tar].freeze
      # The column names and the index of the column of the first one.
      Header = Data.define(:names, :first)
      private_constant :Header

      # sheet: a name, or a position counted from 1 as Excel's tabs are.
      # headers: true (the first row with a value after the skipped ones
      # names the columns), an Array of names, or false. skip: the sheet
      # rows before the header or the data. unpack: what
      # Metacrunch::Input unpacks around a workbook, of :gzip and :tar.
      def initialize(targets, sheet: 1, headers: true, skip: 0, unpack: [:gzip])
        @sheet = check_sheet(sheet)
        @headers = check_headers(headers)
        @skip = check_skip(skip)
        @input = Metacrunch::Input.new(targets, unpack: check_unpack(unpack), packed: :refuse)
      end

      # Without a block an Enumerator.
      def each(&)
        return enum_for(:each) unless block_given?

        @input.each_zip do |zip, name|
          workbook = Workbook.new(zip, name)
          sheet = workbook.sheet(@sheet)
          records(Rows.new(workbook, sheet, name), "#{name}:#{sheet.name}", &)
        end
      rescue Metacrunch::Input::NotZip => e
        raise Metacrunch::InputError, refusal(e)
      end

      def progress = @input.progress

      private

      def check_sheet(sheet)
        return sheet if (sheet.is_a?(String) && !sheet.empty?) || (sheet.is_a?(Integer) && sheet.positive?)

        raise ArgumentError, "sheet must be a name or a position from 1 (sheets count from 1), got #{sheet.inspect}"
      end

      def check_headers(headers)
        return headers if [true, false].include?(headers) || names?(headers)

        raise ArgumentError, "headers must be true, false or an Array of unique, non-empty Strings, " \
                             "got #{headers.inspect}"
      end

      def names?(headers)
        headers.is_a?(Array) && !headers.empty? && headers.all? { it.is_a?(String) && !it.empty? } &&
          headers.uniq.size == headers.size
      end

      def check_unpack(unpack)
        if unpack.is_a?(Array) && unpack.include?(:zip)
          raise ArgumentError, "unpack must not name :zip: a workbook is a zip archive, which is read as one"
        end
        return unpack if unpack.is_a?(Array) && unpack.all? { UNPACK.include?(it) }

        raise ArgumentError, "unpack must be an Array of :gzip and :tar, got #{unpack.inspect}"
      end

      def check_skip(skip)
        return skip if skip.is_a?(Integer) && !skip.negative?

        raise ArgumentError, "skip must be an Integer of 0 or more, got #{skip.inspect}"
      end

      def records(rows, label)
        header = @headers.is_a?(Array) ? Header.new(@headers, 0) : nil
        rows.each do |number, values, defect|
          next if number <= @skip

          if @headers == true && header.nil?
            header = header(values, defect, number, label)
          else
            yield record(values, defect, header, number)
          end
        end
      end

      # Empty columns left of the names are left out: tables often start in
      # column B.
      def header(values, defect, number, label)
        row = "#{label}: the header row (row #{number})"
        raise Metacrunch::InputError, "#{row} cannot be read (#{defect.message})" if defect

        names = values.map { name(it) }
        first = names.index { !it.nil? }
        names = names.drop(first)
        empty = names.index(nil)
        raise Metacrunch::InputError, "#{row} has an empty column name (column #{Cells.column(first + empty)})" if empty

        duplicate = names.find { names.count(it) > 1 }
        raise Metacrunch::InputError, "#{row} names the column #{duplicate.inspect} twice" if duplicate

        Header.new(names, first)
      end

      def name(value)
        case value
        when true then "TRUE"
        when false then "FALSE"
        else value&.to_s
        end
      end

      def record(values, defect, header, number)
        return Metacrunch::InvalidRecord.new(raw: values, error: defect) if defect
        return values unless header

        left = values.index { !it.nil? }
        if left < header.first
          return invalid(values, "row #{number} has a value in column #{Cells.column(left)}, " \
                                 "the header starts at column #{Cells.column(header.first)}")
        end
        last = header.first + header.names.size
        if values.size > last
          return invalid(values, "row #{number} has a value in column #{Cells.column(values.size - 1)}, " \
                                 "the header ends at column #{Cells.column(last - 1)}")
        end

        header.names.each_with_index.to_h { |name, index| [name, values[header.first + index]] }
      end

      def invalid(values, message) = Metacrunch::InvalidRecord.new(raw: values, error: ParseError.new(message))

      def refusal(error)
        if error.head.start_with?(COMPOUND)
          return "#{error.name}: is an Excel 97-2003 workbook (.xls) or an encrypted workbook, which metacrunch " \
                 "cannot read; save it as .xlsx first"
        end

        "#{error.name}: is not an XLSX workbook"
      end

    end
  end
end
