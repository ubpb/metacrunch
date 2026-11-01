# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The parts of a workbook in an Input::Zip, found through its
    # relationships: the sheets, the kinds of the cell formats, the shared
    # strings and the date system. Refuses OpenDocument spreadsheets,
    # binary workbooks and zip archives without a workbook. Internal.
    class Workbook

      # type: :worksheet, :chartsheet, :dialogsheet or :macrosheet.
      Sheet = Data.define(:name, :part, :type)

      ROOT = "_rels/.rels"
      ODS = "application/vnd.oasis.opendocument.spreadsheet"
      # By the last segment of a relationship's type, so that the URIs of
      # Transitional and Strict OOXML both match.
      SHEETS = {"worksheet" => :worksheet, "chartsheet" => :chartsheet, "dialogsheet" => :dialogsheet,
                "xlMacrosheet" => :macrosheet}.freeze
      OTHER_SHEETS = {chartsheet: "a chart sheet", dialogsheet: "a dialog sheet", macrosheet: "a macro sheet"}.freeze
      CANNOT_READ = "which metacrunch cannot read; save it as .xlsx first"
      # Values of a boolean attribute that mean true.
      ON = ["1", "true"].freeze

      attr_reader :sheets

      def initialize(zip, name)
        @zip = zip
        @name = name
        refuse_ods
        @part = office_document
        targets = relationships(@part)
        xml = read(@part)
        @sheets = sheets_of(xml, targets)
        raise InputError, "#{@name}: is a zip archive, but no XLSX workbook" if @sheets.empty?

        @date1904 = elements(xml, "workbookPr", @part).any? { ON.include?(Xml.attributes(it)["date1904"]) }
        @styles = targets.each_value.find { it.first == "styles" }&.last
        @strings = targets.each_value.find { it.first == "sharedStrings" }&.last
      end

      def date1904? = @date1904

      # The sheet of that name, or at that position from 1; a sheet that is
      # no worksheet is refused.
      def sheet(selector)
        sheet = selector.is_a?(Integer) ? @sheets[selector - 1] : @sheets.find { it.name == selector }
        raise InputError, missing(selector) unless sheet
        return sheet if sheet.type == :worksheet

        raise InputError, "#{@name}: sheet #{sheet.name.inspect} is #{OTHER_SHEETS[sheet.type]}"
      end

      # The kind of each cell format (see NumberFormats), by its index in
      # cellXfs; General alone without a styles part, also when the workbook
      # names one the archive lacks.
      def kinds
        @kinds ||= @styles && find(@styles) ? styles : [:number]
      end

      # The texts of the shared-strings table, read on the first call.
      def shared_strings
        return @shared_strings if @shared_strings

        result = []
        each(@strings, "si") { result << Xml.text(it).freeze } if @strings
        @shared_strings = result.freeze
      rescue Xml::Unclosed => e
        raise Xlsx.broken(@name, @strings, e.message)
      end

      # The bytes of a part as a Stream. progress: reading it moves the
      # progress of Input: true for the sheet, not for the parts read before
      # its rows, which writers often put after it.
      def stream(part, progress: false)
        entry = find(part)
        raise Xlsx.broken(@name, part, "named by the workbook, but missing") unless entry

        Input::Stream.new(@zip.member(entry, progress:))
      end

      private

      def refuse_ods
        entry = @zip.entry("mimetype")
        return unless entry && Input::Stream.new(@zip.member(entry, progress: false)).read(ODS.bytesize) == ODS

        raise InputError, "#{@name}: is an OpenDocument spreadsheet (.ods), #{CANNOT_READ}"
      end

      def office_document
        _type, part = relationships(nil).each_value.find { it.first == "officeDocument" }
        raise InputError, "#{@name}: is a binary workbook (.xlsb), #{CANNOT_READ}" if part&.end_with?(".bin")
        raise InputError, "#{@name}: is a zip archive, but no XLSX workbook" unless part && find(part)

        part
      end

      # Id => [type, part] of the relationships of part (nil: the package),
      # internal targets only.
      def relationships(part)
        path = part ? File.join(File.dirname(part), "_rels", "#{File.basename(part)}.rels").delete_prefix("./") : ROOT
        return {} unless find(path)

        result = {}
        each(path, "Relationship") do |element|
          attributes = Xml.attributes(element)
          next if attributes["TargetMode"] == "External"

          result[attributes["Id"]] = [attributes["Type"].to_s.split("/").last, resolve(part, attributes["Target"].to_s)]
        end
        result
      end

      # A target relative to the directory of part, or absolute with "/".
      def resolve(part, target)
        base = target.start_with?("/") || part.nil? ? [] : File.dirname(part).split("/") - ["."]
        target.delete_prefix("/").split("/").each_with_object(base) do |segment, path|
          case segment
          when "..", "." then segment == ".." && path.pop
          else path << segment
          end
        end.join("/")
      end

      def sheets_of(xml, targets)
        elements(xml, "sheet", @part).map do |element|
          attributes = Xml.attributes(element)
          type, part = targets[attributes["id"]]
          raise Xlsx.broken(@name, @part, "sheet #{attributes["name"].inspect} has no relationship") unless part

          Sheet.new(attributes["name"].to_s, part, SHEETS.fetch(type, :worksheet))
        end
      end

      # numFmts holds the custom codes; only cellXfs counts for cells (not
      # cellStyleXfs, not the formats of dxfs).
      def styles
        xml = read(@styles)
        codes = {}
        elements(xml, "numFmts", @styles).each do |list|
          elements(list, "numFmt", @styles).each do |format|
            attributes = Xml.attributes(format)
            codes[attributes["numFmtId"].to_i] = attributes["formatCode"].to_s
          end
        end
        elements(xml, "cellXfs", @styles).flat_map do |list|
          elements(list, "xf", @styles).map do |xf|
            id = Xml.attributes(xf)["numFmtId"].to_i
            NumberFormats.kind(id, codes[id])
          end
        end
      end

      def missing(selector)
        return "#{@name}: has no sheet #{selector}; it has #{@sheets.size}" if selector.is_a?(Integer)

        "#{@name}: has no sheet #{selector.inspect}; its sheets: #{@sheets.map { it.name.inspect }.join(", ")}"
      end

      # The entry of part; another case as a fallback, as some writers
      # name parts differently from their relationships.
      def find(part)
        @zip.entry(part) || (@folded ||= @zip.entries.to_h { [it.name.downcase, it] })[part.downcase]
      end

      def read(part) = stream(part).read

      def each(part, local_name, &) = Xml.each_element(stream(part), local_name, part:, name: @name, &)

      def elements(xml, local_name, part)
        result = []
        Xml.each_element(StringIO.new(xml), local_name, part:, name: @name) { result << it }
        result
      end

    end
  end
end
