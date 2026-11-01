# frozen_string_literal: true

# Builds workbooks for the reader's tests from their parts, so a test can
# give any XML, also XML Excel would not write.
module WorkbookBuilder

  RELATIONSHIPS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  STRICT = "http://purl.oclc.org/ooxml/officeDocument/relationships"

  module_function

  # The bytes of a workbook: sheets maps a sheet name to the XML inside its
  # sheetData; strings are the contents of the shared strings' si
  # elements; formats map a numFmtId to its code, xfs list the numFmtId of
  # each cellXfs entry. extra: more parts, or nil to leave a part out.
  def build(sheets: {"Sheet1" => ""}, strings: nil, xfs: nil, formats: {}, date1904: false, types: RELATIONSHIPS,
            extra: {})
    zip(parts(sheets:, strings:, xfs:, formats:, date1904:, types:).merge(extra).compact)
  end

  def parts(sheets:, strings:, xfs:, formats:, date1904:, types:)
    references = sheets.keys.each_index.map do |index|
      relationship("rId#{index + 1}", "#{types}/worksheet", "worksheets/sheet#{index + 1}.xml")
    end
    references << relationship("rIdS", "#{types}/sharedStrings", "sharedStrings.xml") if strings
    references << relationship("rIdT", "#{types}/styles", "styles.xml") if xfs
    result = {
      "[Content_Types].xml" => "<Types/>",
      "_rels/.rels" => relationships([relationship("rId1", "#{types}/officeDocument", "xl/workbook.xml")]),
      "xl/workbook.xml" => workbook(sheets.keys, date1904),
      "xl/_rels/workbook.xml.rels" => relationships(references)
    }
    sheets.each_value.with_index { |data, index| result["xl/worksheets/sheet#{index + 1}.xml"] = sheet(data) }
    result["xl/sharedStrings.xml"] = "<sst>#{strings.map { "<si>#{it}</si>" }.join}</sst>" if strings
    result["xl/styles.xml"] = styles(xfs, formats) if xfs
    result
  end

  def workbook(names, date1904)
    sheets = names.each_with_index.map do |name, index|
      %(<sheet name="#{name}" sheetId="#{index + 1}" r:id="rId#{index + 1}"/>)
    end
    property = if date1904
      %(<workbookPr date1904="#{date1904 == true ? 1 : date1904}"/>)
    else
      ""
    end
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns:r="#{RELATIONSHIPS}">) +
      %(#{property}<sheets>#{sheets.join}</sheets></workbook>)
  end

  def sheet(data) = %(<?xml version="1.0" encoding="UTF-8"?>\n<worksheet><sheetData>#{data}</sheetData></worksheet>)

  def styles(xfs, formats)
    codes = formats.map { |id, code| %(<numFmt numFmtId="#{id}" formatCode="#{code.encode(xml: :attr)[1..-2]}"/>) }
    cells = xfs.map { %(<xf numFmtId="#{it}" fontId="0"/>) }
    [%(<styleSheet><numFmts count="#{codes.size}">#{codes.join}</numFmts>),
     %(<cellStyleXfs count="1"><xf numFmtId="49"/></cellStyleXfs>),
     %(<cellXfs count="#{cells.size}">#{cells.join}</cellXfs>),
     %(<dxfs count="1"><dxf><numFmt numFmtId="165" formatCode="yyyy"/></dxf></dxfs></styleSheet>)].join
  end

  def relationship(id, type, target) = %(<Relationship Id="#{id}" Type="#{type}" Target="#{target}"/>)

  def relationships(list)
    %(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{list.join}</Relationships>)
  end

  def zip(parts)
    Zip::OutputStream.write_buffer(StringIO.new) do |out|
      parts.each do |name, content|
        out.put_next_entry(name)
        out.write(content)
      end
    end.string
  end

end
