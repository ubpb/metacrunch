# frozen_string_literal: true

# Measures the engine and its executors; not part of the test suite.
#
#   bundle exec ruby -Ilib bench/executor.rb inline|expensive|cheap|jsonl
#
# inline:    1 M records through 10 map steps, without sink, observer or
#            monitor: time per step and record (best of three runs) and
#            allocations per record.
# expensive: 50 k records with string cleaning on every field (ROUNDS=4, about
#            28 µs per record inline), inline and with 8 workers.
# cheap:     1 M records through one cheap map, inline and with 8 workers.
# jsonl:     1 M JSON Lines through a job without steps (exe/metacrunch),
#            inline and with -w 8.

require "metacrunch"
require "open3"
require "tmpdir"

module Bench

  ROOT = File.expand_path("..", __dir__)
  WORKERS = 8

  # Counts what it gets, so records travel back from the workers.
  class Counter

    attr_reader :count

    def initialize
      @count = 0
    end

    def write(_record)
      @count += 1
    end

  end

  module_function

  def build(&)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash({}) }, logger: Logger.new(nil))
    builder.instance_exec(&)
    builder.build
  end

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def inline
    records = Array.new(1_000_000) { it }
    pipeline = build do
      source records
      10.times { map { it } }
    end
    run = -> { Metacrunch::Engine.new(pipeline).run }
    run.call
    best = Array.new(3) { seconds(&run) }.min
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    run.call
    allocations = GC.stat(:total_allocated_objects) - allocated
    format("inline: %<ns>.1f ns per step and record, %<allocations>.1f allocations per record",
           ns: best * 1e9 / (records.size * 10), allocations: allocations.fdiv(records.size))
  end

  def expensive
    rounds = Integer(ENV.fetch("ROUNDS", "4"))
    records = Array.new(50_000) { {"id" => it, "text" => "Ein  Titel mit   Leerraum #{it} " * 4} }
    compare("expensive", records) do |text|
      rounds.times { text = text.unicode_normalize(:nfkc).gsub(/\s+/, " ") }
      text
    end
  end

  def cheap
    compare("cheap", Array.new(1_000_000) { {"id" => it, "text" => "x"} }) { it }
  end

  # Runs the records through one map on "text", inline and with workers.
  # Warms up first (YJIT, lazily loaded tables), so the inline run that
  # comes first is not slower for that.
  def compare(name, records, &)
    records.first(2_000).each { yield(it["text"]) }
    rates = [nil, WORKERS].map do |workers|
      pipeline = build do
        source records
        map { it.merge("text" => yield(it["text"])) }
        sink Counter.new
      end
      records.size / seconds { Metacrunch::Engine.new(pipeline, executor: Metacrunch::Executor.for(workers)).run }
    end
    format("%<name>s: %<us>.1f µs per record inline; inline %<inline>.0f records/s, %<workers>d workers " \
           "%<forked>.0f records/s (%<factor>.1f×)",
           name:, us: 1e6 / rates[0], inline: rates[0], workers: WORKERS, forked: rates[1],
           factor: rates[1] / rates[0])
  end

  def jsonl
    Dir.mktmpdir do |dir|
      input = File.join(dir, "in.jsonl")
      File.write(input, Array.new(1_000_000) { "{\"id\":#{it},\"title\":\"Titel #{it}\"}\n" }.join)
      job = File.join(dir, "pass.rb")
      File.write(job, "# frozen_string_literal: true\n\nMetacrunch.job {}\n")
      rates = [[], ["-w", WORKERS.to_s]].map do |options|
        command = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), "run",
                   *options, "-i", input, "-o", File::NULL, job]
        1_000_000 / seconds { Open3.capture3(*command) }
      end
      format("jsonl: inline %<inline>.0f records/s, -w %<workers>d %<forked>.0f records/s",
             inline: rates[0], workers: WORKERS, forked: rates[1])
    end
  end

end

puts Bench.public_send(ARGV.fetch(0, "inline"))
