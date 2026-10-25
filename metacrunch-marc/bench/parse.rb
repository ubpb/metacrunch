# frozen_string_literal: true

# Measures parsing, splitting, serializing and Marshal on synthetic MARCXML
# with records of about 3 KB.
#
#   bundle exec ruby --yjit bench/parse.rb [RECORDS]
require "metacrunch/marcxml"
require "stringio"
require "tmpdir"
require "zlib"

Marcxml = Metacrunch::Marcxml
COUNT = Integer(ARGV.fetch(0, "10000"))

def record(number)
  fields = [Marcxml::ControlField.new("001", "record-#{number}"),
            Marcxml::ControlField.new("005", "20240101120000.0"),
            Marcxml::ControlField.new("008", "240101s2024    gw            000 0 eng d")]
  12.times do |index|
    subfields = [["a", "Value #{index} of record #{number} with a few words"], ["b", "Second value"],
                 ["0", "(DE-000)#{number}-#{index}"]]
    fields << Marcxml::DataField.new((100 + (index * 60)).to_s, "1", " ", subfields)
  end
  Marcxml::Record.new(leader: "00000nam a2200000 c 4500", type: "Bibliographic", fields:)
end

# The best of three runs.
def measure(label)
  seconds = Array.new(3) do
    GC.start
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end.min
  puts "#{label.ljust(36)} #{format("%.1f", seconds * 1_000_000 / COUNT).rjust(8)} µs/record"
end

records = Array.new(COUNT) { record(it) }
Dir.mktmpdir do |dir|
  path = File.join(dir, "records.xml")
  File.open(path, "w") do |file|
    file.write(Marcxml::Writer::HEADER)
    records.each { file.write(it.to_xml(namespace: false)) }
    file.write(Marcxml::Writer::FOOTER)
  end
  yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? " with YJIT" : ""
  puts "#{COUNT} records of #{File.size(path) / COUNT} bytes, Ruby #{RUBY_VERSION}#{yjit}"

  measure("each (from a file)") { File.open(path) { |io| Marcxml.each(io) { nil } } }
  measure("each (from a StringIO)") { Marcxml.each(StringIO.new(File.read(path))) { nil } }
  measure("each_xml (from a file)") { File.open(path) { |io| Marcxml.each_xml(io) { nil } } }
  measure("Reader (from a file)") { Marcxml::Reader.new(path).each { nil } }
  gzip_path = File.join(dir, "records.xml.gz")
  File.binwrite(gzip_path, Zlib.gzip(File.binread(path)))
  measure("Reader (from a gzip file)") { Marcxml::Reader.new(gzip_path).each { nil } }
  xmls = File.open(path) { Marcxml.each_xml(it).to_a }
  measure("parse (one record string)") { xmls.each { Marcxml.parse(it) } }
  measure("to_xml") { records.each(&:to_xml) }
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
  measure("Marshal round trip of its XML") { xmls.each { Marshal.load(Marshal.dump(it)) } }

  big = Marcxml::Record.new(fields: Array.new(50_000) { Marcxml::DataField.new("500", " ", " ", [["a", "x" * 150]]) })
  big_path = File.join(dir, "big.xml")
  File.write(big_path, big.to_xml)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  File.open(big_path) { |io| Marcxml.each_xml(io) { nil } }
  millis = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  label = "each_xml (one record of #{File.size(big_path) / 1_000_000} MB)"
  puts "#{label.ljust(36)} #{format("%.1f", millis).rjust(8)} ms"
end
