# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # The parts of an XLSX file besides the worksheet. Internal.
    module Package

      MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
      RELATIONSHIPS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
      PACKAGE_RELATIONSHIPS = "http://schemas.openxmlformats.org/package/2006/relationships"
      DECLARATION = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n)
      TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml"

      # Written first: content types, relationships and styles.
      STATIC = {
        "[Content_Types].xml" => <<~XML.delete("\n").freeze,
          #{DECLARATION.chomp}
          <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="#{TYPE}.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="#{TYPE}.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="#{TYPE}.styles+xml"/>
          </Types>
        XML
        "_rels/.rels" => <<~XML.delete("\n").freeze,
          #{DECLARATION.chomp}
          <Relationships xmlns="#{PACKAGE_RELATIONSHIPS}">
          <Relationship Id="rId1" Type="#{RELATIONSHIPS}/officeDocument" Target="xl/workbook.xml"/>
          </Relationships>
        XML
        "xl/_rels/workbook.xml.rels" => <<~XML.delete("\n").freeze,
          #{DECLARATION.chomp}
          <Relationships xmlns="#{PACKAGE_RELATIONSHIPS}">
          <Relationship Id="rId1" Type="#{RELATIONSHIPS}/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="#{RELATIONSHIPS}/styles" Target="styles.xml"/>
          </Relationships>
        XML
        "xl/styles.xml" => <<~XML.delete("\n").freeze
          #{DECLARATION.chomp}
          <styleSheet xmlns="#{MAIN}">
          <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>
          <font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
          <fills count="2"><fill><patternFill patternType="none"/></fill>
          <fill><patternFill patternType="gray125"/></fill></fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
          </styleSheet>
        XML
      }.freeze

      module_function

      # The workbook, written last: it names the autofilter's range
      # (absolute, e.g. "$A$1:$C$10") once the last row is known.
      def workbook(sheet, filter)
        root = %(<workbook xmlns="#{MAIN}" xmlns:r="#{RELATIONSHIPS}">)
        sheets = %(<sheets><sheet name="#{Cells.escape(sheet)}" sheetId="1" r:id="rId1"/></sheets>)
        "#{DECLARATION}#{root}#{sheets}#{defined_names(sheet, filter)}</workbook>"
      end

      # The autofilter's range as Excel names it; the sheet's name is quoted,
      # a ' in it doubled.
      def defined_names(sheet, filter)
        return "" unless filter

        name = %(<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">)
        "<definedNames>#{name}#{Cells.escape("'#{sheet.gsub("'", "''")}'!#{filter}")}</definedName></definedNames>"
      end

    end
  end
end
