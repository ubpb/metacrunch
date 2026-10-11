# frozen_string_literal: true

# Measures the engine and its executors; not part of the test suite.
#
#   bundle exec ruby -Ilib bench/executor.rb inline
#
# inline: 1 M records through 10 map steps, without sink, observer or
# monitor: time per step and record (best of three runs) and allocations
# per record.

require "metacrunch"

module Bench

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

end

puts Bench.public_send(ARGV.fetch(0, "inline"))
