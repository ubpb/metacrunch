# frozen_string_literal: true

# Writes 100,000 rows of 10 text cells and fails when it takes more than 2 s
# or the process holds more than 50 MB at the end (the writer streams, so
# memory stays flat while it runs).
#
#   bundle exec ruby --yjit bench/xlsx.rb [rows]
require "logger"
require "tmpdir"
require "metacrunch/xlsx"

ROWS = Integer(ARGV.fetch(0, 100_000))
SECONDS = 2.0
MEGABYTES = 50

names = Array.new(10) { "column #{it}" }
records = Array.new(1000) { |row| names.each_with_index.to_h { |name, index| [name, "value #{row} #{index}"] } }
ctx = Metacrunch::Context.new(id: 1, position: 1, logger: Logger.new(nil))

Dir.mktmpdir do |dir|
  path = File.join(dir, "out.xlsx")
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  writer = Metacrunch::Xlsx::Writer.new(path)
  writer.open(nil)
  ROWS.times { writer.write(records[it % records.size], ctx) }
  writer.close
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  megabytes = Integer(`ps -o rss= -p #{Process.pid}`) / 1024

  puts format("%<rows>d rows: %<seconds>.2f s, %<megabytes>d MB, file %<size>d KB",
              rows: ROWS, seconds:, megabytes:, size: File.size(path) / 1024)
  exit(1) if seconds > SECONDS || megabytes > MEGABYTES
end
