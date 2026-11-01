# frozen_string_literal: true

# Reads 100,000 rows of 10 cells from a workbook as Excel writes it (shared
# strings from 10,000 texts, styles, a date and a date-time column) and
# fails when it takes more than 3 s or the process holds more than 80 MB at
# its peak.
#
#   bundle exec ruby --yjit bench/reader.rb [rows]
require "tmpdir"
require "metacrunch/xlsx"

ROWS = Integer(ARGV.fetch(0, 100_000))
SECONDS = 3.0
MEGABYTES = 80
TEXTS = 10_000
NAMESPACE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PACKAGE = "http://schemas.openxmlformats.org/package/2006/relationships"

# The resident size of this process in KB.
def rss = Integer(`ps -o rss= -p #{Process.pid}`)

# The largest resident size in MB while the block runs, sampled every 0.2 s.
def peak_megabytes
  peak = rss
  sampler = Thread.new do
    loop do
      sleep 0.2
      peak = [peak, rss].max
    end
  end
  yield
  sampler.kill.join
  [peak, rss].max / 1024
end

# list: [id, type, target] of each relationship.
def relationships(*list)
  entries = list.map do |id, type, target|
    %(<Relationship Id="#{id}" Type="#{NAMESPACE}/#{type}" Target="#{target}"/>)
  end
  %(<Relationships xmlns="#{PACKAGE}">#{entries.join}</Relationships>)
end

def workbook_xml
  %(<workbook xmlns:r="#{NAMESPACE}"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>)
end

def styles_xml
  %(<styleSheet><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="22"/></cellXfs></styleSheet>)
end

# Five text columns, three numbers, a date and a date-time, as Excel stores
# them; written in a stream, so the bench measures the reader only.
def write_workbook(path)
  File.open(path, "wb") do |file|
    ZipKit::Streamer.open(file) do |zip|
      zip.write_deflated_file("[Content_Types].xml") { |out| out << "<Types/>" }
      zip.write_deflated_file("_rels/.rels") do |out|
        out << relationships(["rId1", "officeDocument", "xl/workbook.xml"])
      end
      zip.write_deflated_file("xl/workbook.xml") { |out| out << workbook_xml }
      zip.write_deflated_file("xl/_rels/workbook.xml.rels") do |out|
        out << relationships(["rId1", "worksheet", "worksheets/sheet1.xml"],
                             ["rId2", "sharedStrings", "sharedStrings.xml"], ["rId3", "styles", "styles.xml"])
      end
      zip.write_deflated_file("xl/styles.xml") { |out| out << styles_xml }
      zip.write_deflated_file("xl/sharedStrings.xml") { |out| write_strings(out) }
      zip.write_deflated_file("xl/worksheets/sheet1.xml") { |out| write_sheet(out) }
    end
  end
end

def write_strings(out)
  out << %(<sst count="#{TEXTS}" uniqueCount="#{TEXTS}">)
  TEXTS.times { out << "<si><t>text number #{it} of the shared strings</t></si>" }
  out << "</sst>"
end

def write_sheet(out)
  out << %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet><sheetData>)
  header = ("A".."J").map { %(<c r="#{it}1" t="inlineStr"><is><t>column #{it}</t></is></c>) }
  out << %(<row r="1">#{header.join}</row>)
  ROWS.times { out << row(it) }
  out << "</sheetData></worksheet>"
end

def row(index)
  number = index + 2
  serial = 40_000 + (index % 3000)
  texts = ("A".."E").each_with_index.map do |column, offset|
    %(<c r="#{column}#{number}" t="s"><v>#{((index * 5) + offset) % TEXTS}</v></c>)
  end
  [%(<row r="#{number}" spans="1:10">), *texts,
   %(<c r="F#{number}"><v>#{index}</v></c><c r="G#{number}"><v>#{index * 1.25}</v></c>),
   %(<c r="H#{number}"><v>-#{index}.5</v></c><c r="I#{number}" s="1"><v>#{serial}</v></c>),
   %(<c r="J#{number}" s="2"><v>#{serial}.604166666666667</v></c></row>)].join
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "bench.xlsx")
  write_workbook(path)
  GC.start
  count = 0
  seconds = nil
  megabytes = peak_megabytes do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Metacrunch::Xlsx::Reader.new(path).each { count += 1 }
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end

  puts format("%<rows>d rows: %<seconds>.2f s, peak %<megabytes>d MB, file %<size>d KB",
              rows: count, seconds:, megabytes:, size: File.size(path) / 1024)
  exit(1) if seconds > SECONDS || megabytes > MEGABYTES
end
