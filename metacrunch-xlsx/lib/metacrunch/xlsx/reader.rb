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

      # sheet: a name, or a position counted from 1 as Excel's tabs are.
      # headers: true (the first row with a value after the skipped ones
      # names the columns), an Array of names, or false. skip: the sheet
      # rows before the header or the data. unpack: what
      # Metacrunch::Input unpacks around a workbook, of :gzip and :tar.
      def initialize(targets, sheet: 1, headers: true, skip: 0, unpack: [:gzip])
        @sheet = check_sheet(sheet)
        @headers = check_headers(headers)
        @skip = check_skip(skip)
        if unpack.is_a?(Array) && unpack.include?(:zip)
          raise ArgumentError, "unpack must not name :zip: a workbook is a zip archive, which is read as one"
        end

        @input = Metacrunch::Input.new(targets, unpack:, packed: :refuse)
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

      def check_skip(skip)
        return skip if skip.is_a?(Integer) && !skip.negative?

        raise ArgumentError, "skip must be an Integer of 0 or more, got #{skip.inspect}"
      end

      def records(rows, label)
        names = @headers.is_a?(Array) ? @headers : nil
        rows.each do |number, values, defect|
          next if number <= @skip

          if @headers == true && names.nil?
            names = header(values, defect, number, label)
          else
            yield record(values, defect, names, number)
          end
        end
      end

      def header(values, defect, number, label)
        row = "#{label}: the header row (row #{number})"
        raise Metacrunch::InputError, "#{row} cannot be read (#{defect.message})" if defect

        names = values.map { name(it) }
        empty = names.index(nil)
        raise Metacrunch::InputError, "#{row} has an empty column name (column #{Cells.column(empty)})" if empty

        duplicate = names.find { names.count(it) > 1 }
        raise Metacrunch::InputError, "#{row} names the column #{duplicate.inspect} twice" if duplicate

        names
      end

      def name(value)
        case value
        when true then "TRUE"
        when false then "FALSE"
        else value&.to_s
        end
      end

      def record(values, defect, names, number)
        return Metacrunch::InvalidRecord.new(raw: values, error: defect) if defect
        return values unless names
        return names.each_with_index.to_h { |name, index| [name, values[index]] } if values.size <= names.size

        error = ParseError.new("row #{number} has a value in column #{Cells.column(values.size - 1)}, " \
                               "the header ends at column #{Cells.column(names.size - 1)}")
        Metacrunch::InvalidRecord.new(raw: values, error:)
      end

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
