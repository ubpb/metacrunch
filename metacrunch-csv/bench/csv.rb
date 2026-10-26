# frozen_string_literal: true

# Reads and writes 1 million CSV rows with metacrunch-csv and with Ruby's csv
# and fails when metacrunch-csv takes more than 1.3 times as long.
#
#   bundle exec ruby --yjit bench/csv.rb [rows]
require "logger"
require "tmpdir"
require "metacrunch/csv"

ROWS = Integer(ARGV.fetch(0, 1_000_000))
LIMIT = 1.3

def best_of_three
  Array.new(3) do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end.min
end

# Prints the times; true if metacrunch-csv stays within LIMIT.
def within_limit?(name, ruby, ours)
  ratio = ours / ruby
  puts format("%<name>-5s Ruby's csv %<ruby>.2f s, metacrunch-csv %<ours>.2f s (%<ratio>.2f times)",
              name:, ruby:, ours:, ratio:)
  ratio <= LIMIT
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "data.csv")
  File.open(path, "w") do |file|
    file.puts("id,title,year,isbn")
    ROWS.times { file.puts(%(#{it},"Title, number #{it}",#{1900 + (it % 120)},978316148410#{it % 10})) }
  end

  ruby = best_of_three { CSV.foreach(path, headers: true, &:to_h) }
  ours = best_of_three { Metacrunch::Csv::Reader.new(path).each { nil } }
  read = within_limit?("read", ruby, ours)

  records = Metacrunch::Csv::Reader.new(path).each.to_a
  ctx = Metacrunch::Context.new(id: 1, position: 1, logger: Logger.new(nil))
  output = File.join(dir, "out.csv")
  ruby = best_of_three do
    File.open(output, "w") { |file| records.each { file.write(CSV.generate_line(it.values)) } }
  end
  ours = best_of_three do
    writer = Metacrunch::Csv::Writer.new(output)
    writer.open(nil)
    records.each { writer.write(it, ctx) }
    writer.close
  end

  exit(1) unless [read, within_limit?("write", ruby, ours)].all?
end
