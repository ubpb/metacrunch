# frozen_string_literal: true

module Metacrunch
  # Mutable counters used by the engine during a run. #snapshot returns
  # an immutable Stats.
  class StatsCollector

    StepCounter = Struct.new(:input, :output, :filtered, :rejected, :failed, :time)

    attr_reader :read, :rejected_total, :failed_total

    def initialize(step_names, profile: false)
      @profile = profile
      @read = 0
      @written = 0
      @rejected = Hash.new(0)
      @marked = Hash.new(0)
      @failed = Hash.new(0)
      @failed_total = 0
      @rejected_total = 0
      @steps = step_names.to_h { |name| [name, StepCounter.new(0, 0, 0, 0, 0, profile ? 0.0 : nil)] }
      @started_at = now
    end

    def profile?
      @profile
    end

    # The mutable counter of one step. The engine resolves it once per step
    # and updates input, output and filtered directly.
    def counter(name)
      @steps.fetch(name)
    end

    def count_read
      @read += 1
    end

    def count_written(count = 1)
      @written += count
    end

    def step_rejected(name, reason)
      @steps.fetch(name).rejected += 1
      @rejected[reason] += 1
      @rejected_total += 1
    end

    def step_failed(name, error)
      @steps.fetch(name).failed += 1
      source_failed(error)
    end

    # A record the source could not read (InvalidRecord). It has no step,
    # so only the job-level counts change.
    def source_failed(error)
      @failed[error.class.name] += 1
      @failed_total += 1
    end

    def step_time(name, seconds)
      @steps.fetch(name).time += seconds
    end

    def mark(reason)
      @marked[reason] += 1
    end

    # Iterates only the step counters, whose Hash never changes during a
    # run, so another thread may call it.
    def filtered_total
      @steps.each_value.sum(&:filtered)
    end

    def elapsed
      now - @started_at
    end

    def snapshot
      Stats.new(
        read: @read,
        written: @written,
        filtered: filtered_total,
        rejected: @rejected.dup,
        marked: @marked.dup,
        failed: @failed.dup,
        steps: @steps.transform_values { |counter| StepStats.new(**counter.to_h) },
        duration: elapsed
      )
    end

    # Returns the counts since the last take as Stats and sets them to
    # zero. The step counters stay the same objects, so a chain built on
    # them keeps counting. Workers report each batch this way.
    def take
      snapshot.tap { reset }
    end

    # Adds what another collector counted (a Stats from take or snapshot),
    # e.g. a batch of a worker.
    def absorb(stats)
      @read += stats.read
      @written += stats.written
      add_counts(@rejected, stats.rejected)
      add_counts(@marked, stats.marked)
      add_counts(@failed, stats.failed)
      @rejected_total += stats.rejected_total
      @failed_total += stats.failed_total
      stats.steps.each { |name, step| add_step(@steps.fetch(name), step) }
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def reset
      @read = 0
      @written = 0
      @rejected = Hash.new(0)
      @marked = Hash.new(0)
      @failed = Hash.new(0)
      @failed_total = 0
      @rejected_total = 0
      @steps.each_value do |counter|
        counter.members.each { counter[it] = 0 }
        counter.time = @profile ? 0.0 : nil
      end
    end

    def add_counts(mine, theirs)
      theirs.each { |key, count| mine[key] += count }
    end

    def add_step(counter, step)
      counter.input += step.input
      counter.output += step.output
      counter.filtered += step.filtered
      counter.rejected += step.rejected
      counter.failed += step.failed
      counter.time += step.time if counter.time && step.time
    end

  end
end
