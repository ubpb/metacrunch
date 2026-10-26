# frozen_string_literal: true

module Metacrunch
  module Csv
    # A metacrunch source: reads CSV from what Metacrunch::Input reads
    # (paths, "-" for stdin, IOs or an Array of them; gzip and tar are
    # unpacked) and yields a Hash per row (String keys and values, "" for an
    # empty field, nil for a missing one), or an Array with headers: false.
    # A row that cannot be read is yielded as Metacrunch::InvalidRecord.
    class Reader

      def initialize(targets, col_sep: ",", quote_char: '"', encoding: "UTF-8", headers: true)
        @input = Metacrunch::Input.new(targets)
        @encoding = Csv.encoding(col_sep, quote_char, encoding)
        @headers = check_headers(headers)
        # Ruby's csv cannot go on after invalid bytes. Where it can parse the
        # bytes (Csv.bytewise?), the reader checks every value, and a row with
        # invalid bytes becomes an InvalidRecord; other encodings (UTF-16, ...)
        # are parsed in the encoding, and invalid bytes stop the document.
        @bytewise = Csv.bytewise?(@encoding)
        @parse_encoding = @bytewise ? Encoding::BINARY : @encoding
        @options = {col_sep: syntax(col_sep), quote_char: syntax(quote_char), skip_blanks: true}
      end

      # Without a block an Enumerator.
      def each(&)
        return enum_for(:each) unless block_given?

        @input.each_document { |stream, name| read_document(stream, name, &) }
      end

      # The share of the input read so far; see Metacrunch::Input#progress.
      def progress = @input.progress

      private

      def check_headers(headers)
        return headers if [true, false].include?(headers) || names?(headers)

        raise ArgumentError, "headers must be true, false or an Array of unique, non-empty Strings, " \
                             "got #{headers.inspect}"
      end

      def names?(headers)
        headers.is_a?(Array) && !headers.empty? && headers.all? { it.is_a?(String) && !it.empty? } &&
          headers.uniq.size == headers.size
      end

      def syntax(text) = @bytewise ? text.encode(@encoding).b : text.encode(@encoding)

      def read_document(stream, name, &)
        skip_bom(stream)
        csv = ::CSV.new(Lines.new(stream, @parse_encoding), **@options)
        names = @headers == true ? header(csv, name) : @headers
        while (fields = next_fields(csv, name, &))
          next if fields == :invalid

          yield names ? record(fields, names, csv) : fields
        end
      end

      def skip_bom(stream)
        bom = BOMS[@encoding]
        stream.read(bom.bytesize) if bom && stream.peek(bom.bytesize) == bom
      end

      # The column names from the first row; nil for an empty document.
      def header(csv, name)
        fields = next_fields(csv, name) do |invalid|
          raise InputError, "#{name}: the header row cannot be read (#{invalid.error.message})"
        end
        return if fields.nil?

        empty = fields.index(&:empty?)
        raise InputError, "#{name}: the header row has an empty column name (column #{empty + 1})" if empty

        duplicate = fields.find { fields.count(it) > 1 }
        raise InputError, "#{name}: the header row names the column #{duplicate.inspect} twice" if duplicate

        fields
      end

      # The next row's fields in UTF-8, nil at the end, or :invalid after
      # yielding an InvalidRecord for a row that cannot be read.
      def next_fields(csv, name)
        fields = csv.shift
        return if fields.nil?

        fields.map! { value(it, csv) }
      rescue ::CSV::MalformedCSVError, EncodingError => e
        if e.is_a?(::CSV::InvalidEncodingError) && !@bytewise
          raise InputError, "#{name}: the data is not valid #{@encoding}"
        end

        yield invalid(csv.line, e)
        :invalid
      end

      def value(field, csv)
        return +"" if field.nil?
        return field.encode(Encoding::UTF_8) unless @bytewise

        field.force_encoding(@encoding)
        raise ::CSV::InvalidEncodingError.new(@encoding, csv.lineno) unless field.valid_encoding?

        @encoding == Encoding::UTF_8 ? field : field.encode(Encoding::UTF_8)
      end

      def record(fields, names, csv)
        if fields.size > names.size
          return invalid(csv.line, ParseError.new("row has #{fields.size} fields, the header #{names.size}"))
        end

        names.zip(fields).to_h
      end

      def invalid(line, error)
        raw = line.to_s.dup.force_encoding(@encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        Metacrunch::InvalidRecord.new(raw: raw.scrub.chomp, error:)
      end

    end
  end
end
