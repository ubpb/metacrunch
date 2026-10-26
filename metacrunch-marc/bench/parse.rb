# frozen_string_literal: true

# Measures parsing, splitting, serializing and Marshal for MARCXML, ISO 2709
# and MARC-in-JSON, on synthetic records of about 3 KB as MARCXML.
#
#   bundle exec ruby --yjit bench/parse.rb [RECORDS]
require "json"
require "metacrunch/marc"
require "stringio"
require "tmpdir"
require "zlib"
require_relative "records"

Marc = Metacrunch::Marc
COUNT = Integer(ARGV.fetch(0, "10000"))
LIBRARIES = {"MARCXML" => Marc::Xml, "ISO 2709" => Marc::Iso2709, "MARC-in-JSON" => Marc::Json}.freeze

# The best of three runs.
def measure(label)
  seconds = Array.new(3) do
    GC.start
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end.min
  puts "#{label.ljust(52)} #{format("%.1f", seconds * 1_000_000 / COUNT).rjust(8)} µs/record"
end

def milliseconds(label)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  millis = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  puts "#{label.ljust(52)} #{format("%.1f", millis).rjust(8)} ms"
end

def write(path, content)
  File.binwrite(path, content)
  path
end

records = Array.new(COUNT) { record(it) }
Dir.mktmpdir do |dir|
  paths = {
    "MARCXML" => write(File.join(dir, "records.xml"),
                       Marc::Xml::HEADER + records.map { it.to_xml(namespace: false) }.join + Marc::Xml::FOOTER),
    "ISO 2709" => write(File.join(dir, "records.mrc"), records.map(&:to_iso2709).join),
    "MARC-in-JSON" => write(File.join(dir, "records.jsonl"), records.map { "#{it.to_json}\n" }.join)
  }
  yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? " with YJIT" : ""
  sizes = paths.map { |name, path| "#{name} #{File.size(path) / COUNT} bytes" }.join(", ")
  puts "#{COUNT} records (#{sizes} per record), Ruby #{RUBY_VERSION}#{yjit}"

  LIBRARIES.each do |name, library|
    path = paths.fetch(name)
    raws = File.open(path) { library.each_raw(it).to_a }
    gzip = write("#{path}.gz", Zlib.gzip(File.binread(path)))
    measure("#{name}: parse (one record string)") { raws.each { library.parse(it) } }
    measure("#{name}: each_raw (from a file)") { File.open(path) { |io| library.each_raw(io) { nil } } }
    measure("#{name}: each (from a file)") { File.open(path) { |io| library.each(io) { nil } } }
    measure("#{name}: Reader (from a file)") { Marc::Reader.new(path).each { nil } }
    measure("#{name}: Reader (from a gzip file)") { Marc::Reader.new(gzip).each { nil } }
    measure("#{name}: Marshal round trip of a record string") { raws.each { Marshal.load(Marshal.dump(it)) } }
  end
  isos = records.map(&:to_iso2709)
  measure("MARCXML: each (from a StringIO)") { Marc::Xml.each(StringIO.new(File.read(paths["MARCXML"]))) { nil } }
  measure("Marc.parse (an ISO 2709 record string)") { isos.each { Marc.parse(it) } }
  measure("to_xml") { records.each(&:to_xml) }
  measure("to_iso2709") { records.each(&:to_iso2709) }
  measure("to_json") { records.each(&:to_json) }
  measure("8 queries") do
    records.each do |r|
      r["001"]&.value
      r.field("540", ind2: "1")
      r.values("580", "a", ind1: "1", ind2: ["0", "2", " "])
      r.values("160", "a", "0", ind1: "1")
      r.value("220", "a")
      r.fields("700").map { it.value("a") }
      r.values("100", "a", ind1: "1")
      r.values("400", "b")
    end
  end
  measure("Marshal round trip of a record") { records.each { Marshal.load(Marshal.dump(it)) } }

  big = Marc::Record.new(fields: Array.new(50_000) { Marc::DataField.new("500", " ", " ", [["a", "x" * 150]]) })
  big_xml = write(File.join(dir, "big.xml"), big.to_xml)
  big_iso = write(File.join(dir, "big.mrc"), big.to_iso2709(oversize: :allow))
  milliseconds("MARCXML: each_raw (one record of #{File.size(big_xml) / 1_000_000} MB)") do
    File.open(big_xml) { |io| Marc::Xml.each_raw(io) { nil } }
  end
  milliseconds("ISO 2709: each (one record of #{File.size(big_iso) / 1_000_000} MB)") do
    File.open(big_iso) { |io| Marc::Iso2709.each(io) { nil } }
  end
end
