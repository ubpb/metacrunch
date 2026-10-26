# frozen_string_literal: true

# Compares metacrunch-marc with ruby-marc 1.4 on real records: the Library of
# Congress "Books All" 2016 part 1, 250,000 records as UTF-8 ISO 2709 and as
# MARCXML (https://www.loc.gov/cds/products/marcDist.php). Download and unpack
# them into DIR first:
#
#   curl -O https://www.loc.gov/cds/downloads/MDSConnect/BooksAll.2016.part01.utf8.gz
#   curl -O https://www.loc.gov/cds/downloads/MDSConnect/BooksAll.2016.part01.xml.gz
#   gunzip BooksAll.2016.part01.*.gz
#   bundle exec ruby --yjit bench/ruby_marc.rb DIR
#
# It checks that both read the same records, then measures reading, memory,
# writing and queries. Records metacrunch-marc rejects are left out of the
# ISO 2709 measurements, so that both read the same records. Takes about
# ten minutes.
require "json"
require "marc"
require "metacrunch/marc"
require "nokogiri"
require "objspace"
require "tmpdir"

Marc = Metacrunch::Marc
DIR = ARGV.fetch(0) { abort "usage: bundle exec ruby --yjit bench/ruby_marc.rb DIR (see the comment at the top)" }
ISO = File.join(DIR, "BooksAll.2016.part01.utf8")
XML = File.join(DIR, "BooksAll.2016.part01.xml")
RUNS = 2
HELD = 50_000
SAMPLE = 10_000

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def row(label, *columns) = puts("  #{label.ljust(50)} #{columns.join(" ")}")

# The best of runs, and the objects the first run allocated.
def measure(label, count, runs: RUNS)
  allocated = nil
  seconds = Array.new(runs) do
    GC.start
    before = GC.stat(:total_allocated_objects)
    started = clock
    yield
    elapsed = clock - started
    allocated ||= GC.stat(:total_allocated_objects) - before
    elapsed
  end.min
  row(label, "#{format("%.1f", seconds * 1_000_000 / count).rjust(7)} µs/record",
      "#{(count / seconds).round.to_s.rjust(8)} records/s",
      "#{allocated.fdiv(count).round.to_s.rjust(5)} objects/record")
end

# The objects and bytes each record keeps when HELD records are held.
def held(label)
  GC.start
  slots = GC.stat(:heap_live_slots)
  bytes = ObjectSpace.memsize_of_all
  records = yield
  GC.start
  row(label, "#{(GC.stat(:heap_live_slots) - slots).fdiv(HELD).round.to_s.rjust(7)} objects/record",
      "#{(ObjectSpace.memsize_of_all - bytes).fdiv(HELD).round.to_s.rjust(6)} bytes/record")
  records
end

# Our records as Hashes, or the ParseError of a record.
def ours(library, path)
  Enumerator.new do |yielder|
    File.open(path, "rb") do |io|
      library.each_raw(io) do |raw|
        yielder << library.parse(raw).to_h
      rescue Marc::ParseError => e
        yielder << e
      end
    end
  end
end

def compare(label, ours, theirs)
  counts = Hash.new(0)
  rejected = nil
  ours.zip(theirs) do |mine, other|
    if mine.is_a?(Marc::ParseError)
      counts[:rejected] += 1
      rejected ||= mine.message
    else
      counts[mine == other.to_hash ? :same : :different] += 1
    end
  end
  row(label, "#{counts[:same]} the same, #{counts[:different]} different, #{counts[:rejected]} rejected")
  puts "    e.g. #{rejected}" if rejected
end

yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? " with YJIT" : ""
puts "Ruby #{RUBY_VERSION}#{yjit}, metacrunch-marc #{Marc::VERSION}, ruby-marc #{MARC::VERSION}, Ox #{Ox::VERSION}, " \
     "Nokogiri #{Nokogiri::VERSION}"

puts "\nThe same records? (metacrunch-marc to_h against ruby-marc to_hash)"
compare("ISO 2709", ours(Marc::Iso2709, ISO), MARC::Reader.new(ISO, external_encoding: "UTF-8").each)
compare("MARCXML", ours(Marc::Xml, XML), MARC::XMLReader.new(XML, parser: "nokogiri").each)

Dir.mktmpdir do |tmp|
  iso = File.join(tmp, "accepted.mrc")
  sample = File.join(tmp, "sample.xml")
  File.open(iso, "wb") do |out|
    File.open(ISO, "rb") do |io|
      Marc::Iso2709.each_raw(io) do |raw|
        Marc::Iso2709.parse(raw)
        out.write(raw)
      rescue Marc::ParseError
        nil
      end
    end
  end
  File.open(XML, "rb") do |io|
    File.write(sample, "#{Marc::Xml::HEADER}#{Marc::Xml.each_raw(io).first(SAMPLE).join("\n")}\n#{Marc::Xml::FOOTER}")
  end
  iso_count = File.open(iso, "rb") { |io| Marc::Iso2709.each_raw(io).count }
  xml_count = File.open(XML, "rb") { |io| Marc::Xml.each_raw(io).count }

  puts "\nRead ISO 2709: #{iso_count} records, #{File.size(iso) / iso_count} bytes per record, best of #{RUNS}"
  measure("metacrunch-marc Iso2709.each", iso_count) { File.open(iso, "rb") { |io| Marc::Iso2709.each(io) { nil } } }
  measure("metacrunch-marc Reader", iso_count) { Marc::Reader.new(iso).each { nil } }
  measure("ruby-marc MARC::Reader", iso_count) { MARC::Reader.new(iso, external_encoding: "UTF-8").each { nil } }

  puts "\nRead MARCXML: #{xml_count} records, #{File.size(XML) / xml_count} bytes per record, best of #{RUNS}"
  measure("metacrunch-marc Xml.each (Ox)", xml_count) { File.open(XML, "rb") { |io| Marc::Xml.each(io) { nil } } }
  measure("metacrunch-marc Reader", xml_count) { Marc::Reader.new(XML).each { nil } }
  measure("ruby-marc MARC::XMLReader (Nokogiri)", xml_count) do
    MARC::XMLReader.new(XML, parser: "nokogiri").each { nil }
  end
  puts "\nRead the first #{SAMPLE} records of the MARCXML"
  measure("metacrunch-marc Xml.each (Ox)", SAMPLE) { File.open(sample, "rb") { |io| Marc::Xml.each(io) { nil } } }
  measure("ruby-marc MARC::XMLReader (Nokogiri)", SAMPLE) do
    MARC::XMLReader.new(sample, parser: "nokogiri").each { nil }
  end
  measure("ruby-marc MARC::XMLReader (REXML, its default)", SAMPLE, runs: 1) do
    MARC::XMLReader.new(sample, parser: "rexml").each { nil }
  end

  puts "\nHold #{HELD} records read from the ISO 2709"
  ours = held("metacrunch-marc") { File.open(iso, "rb") { |io| Marc::Iso2709.each(io).first(HELD) } }
  theirs = held("ruby-marc") { MARC::Reader.new(iso, external_encoding: "UTF-8").first(HELD) }

  puts "\nWrite #{HELD} records"
  measure("metacrunch-marc Record#to_iso2709", HELD) { ours.each(&:to_iso2709) }
  measure("ruby-marc MARC::Record#to_marc", HELD) { theirs.each(&:to_marc) }
  measure("metacrunch-marc Record#to_xml", HELD) { ours.each(&:to_xml) }
  measure("ruby-marc #to_xml_string (REXML)", HELD, runs: 1) { theirs.each(&:to_xml_string) }
  measure("ruby-marc #to_xml_string(fast_but_unsafe: true)", HELD) do
    theirs.each { it.to_xml_string(fast_but_unsafe: true) }
  end
  measure("metacrunch-marc Record#to_json", HELD) { ours.each(&:to_json) }
  measure("ruby-marc JSON.generate(MARC::Record#to_hash)", HELD) { theirs.each { JSON.generate(it.to_hash) } }

  puts "\nQuery #{HELD} records: 245 $a, 100 $a, 008, $a of every 020 and 650"
  measure("metacrunch-marc", HELD) do
    ours.each do |record|
      record.value("245", "a")
      record.value("100", "a")
      record["008"]&.value
      record.values("020", "a")
      record.values("650", "a")
    end
  end
  measure("ruby-marc", HELD) do
    theirs.each do |record|
      record["245"]&.[]("a")
      record["100"]&.[]("a")
      record["008"]&.value
      record.fields("020").map { it["a"] }
      record.fields("650").map { it["a"] }
    end
  end
end
