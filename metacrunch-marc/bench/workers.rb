# frozen_string_literal: true

# Measures a MARC to MARC job (MARCXML in and out, one cheap step that adds
# a field) inline and with workers, on synthetic records of about 3 KB as
# MARCXML. The workers get Records or Strings, and send back Records or
# MARCXML Strings (see "Workers" in the Readme).
#
#   bundle exec ruby --yjit bench/workers.rb [RECORDS] [WORKERS]
require "etc"
require "logger"
require "metacrunch/marc"
require "tmpdir"
require_relative "records"

Marc = Metacrunch::Marc
COUNT = Integer(ARGV.fetch(0, "100000"))
WORKERS = Integer(ARGV.fetch(1, "4"))
MARK = Marc::DataField.new("999", " ", " ", [["a", "processed"]]).freeze

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Records per second of the job, the best of two runs. parse: whether the
# reader parses (else the first step does); serialize: whether the last step
# writes MARCXML (else the writer does).
def rate(path, target, workers:, parse:, serialize:)
  job = Metacrunch.job do
    source Marc::Reader.new(path, parse:)
    map(name: "parse") { Marc.parse(it) } unless parse
    map(name: "mark") { it.add(MARK.dup) }
    map(name: "serialize") { it.to_xml(namespace: false) } if serialize
    sink Marc::Writer.new(target, format: :xml)
  end
  seconds = Array.new(2) do
    started = clock
    result = job.run(workers:, logger: Logger.new(nil))
    raise "#{result.status}: #{result.error}" unless result.status == :ok

    clock - started
  end.min
  COUNT / seconds
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "records.xml")
  File.open(path, "w") do |file|
    file << Marc::Xml::HEADER
    COUNT.times { file << record(it).to_xml(namespace: false) << "\n" }
    file << Marc::Xml::FOOTER
  end
  target = File.join(dir, "out.xml")
  yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? " with YJIT" : ""
  puts "#{COUNT} records (#{File.size(path) / COUNT} bytes per record as MARCXML), Ruby #{RUBY_VERSION}#{yjit}, " \
       "#{Etc.nprocessors} processors"

  [
    ["inline, the reader parses", nil, true, false],
    ["#{WORKERS} workers, the reader parses, Records back", WORKERS, true, false],
    ["#{WORKERS} workers, a step parses, Records back", WORKERS, false, false],
    ["#{WORKERS} workers, a step parses, MARCXML back", WORKERS, false, true],
    ["inline, a step parses, MARCXML back", nil, false, true]
  ].each do |label, workers, parse, serialize|
    records_per_second = rate(path, target, workers:, parse:, serialize:)
    puts "  #{label.ljust(52)} #{records_per_second.round.to_s.rjust(7)} records/s"
  end
end
