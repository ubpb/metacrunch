# frozen_string_literal: true

# Measures reading and writing JSON Lines through JsonLines::Reader and
# JsonLines::Writer; not part of the test suite.
#
#   bundle exec ruby --yjit -Ilib bench/io.rb [LINES]
#
# Reads LINES lines (default 1 M) from a plain and a gzip file and writes
# up to 300 k of them; best of three runs each.

require "metacrunch"
require "tmpdir"
require "zlib"

module Bench

  LINES = Integer(ARGV.fetch(0, "1000000"))
  WRITTEN = [LINES, 300_000].min

  module_function

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def best(&) = Array.new(3) { seconds(&) }.min

  def report(label, seconds, count)
    per_line = format("%.3f", seconds * 1e6 / count)
    puts "#{label.ljust(16)} #{format("%.3f", seconds).rjust(7)} s #{per_line.rjust(7)} µs/line"
  end

  def record(number) = {"id" => number, "title" => "Title number #{number} " * 3, "year" => number % 120}

  def run
    Dir.mktmpdir do |dir|
      plain = File.join(dir, "records.jsonl")
      File.open(plain, "w") { |file| LINES.times { file.puts(JSON.generate(record(it))) } }
      gzip = File.join(dir, "records.jsonl.gz")
      Zlib::GzipWriter.open(gzip) { |out| File.open(plain, "rb") { IO.copy_stream(it, out) } }

      report("read plain", best { Metacrunch::JsonLines::Reader.new(plain).enum_for(:each).each { nil } }, LINES)
      report("read gzip", best { Metacrunch::JsonLines::Reader.new(gzip).enum_for(:each).each { nil } }, LINES)
      records = Metacrunch::JsonLines::Reader.new(plain).enum_for(:each).first(WRITTEN)
      ctx = Metacrunch::Context.new(id: 1, position: 1, logger: Logger.new(nil))
      output = File.join(dir, "out.jsonl")
      written = best do
        writer = Metacrunch::JsonLines::Writer.new(output)
        writer.open(nil)
        records.each { writer.write(it, ctx) }
        writer.close
      end
      report("write", written, WRITTEN)
    end
  end

end

Bench.run
