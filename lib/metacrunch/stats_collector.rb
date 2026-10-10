# frozen_string_literal: true

module Metacrunch
  # Mutable counters used by the engine during a run. #snapshot returns
  # an immutable Stats.
  class StatsCollector

    StepCounter = Struct.new(:input, :output, :filtered, :rejected, :failed, :time)

    def initialize(step_names, profile: false)
      @profile = profile
      @read = 0
      @written = 0
      @rejected = Hash.new(0)
      @marked = Hash.new(0)
      @failed = Hash.new(0)
      @steps = step_names.to_h { |name| [name, StepCounter.new(0, 0, 0, 0, 0, profile ? 0.0 : nil)] }
      @started_at = now
    end

    def profile?
      @profile
    end

    def count_read
      @read += 1
    end

    def count_written
      @written += 1
    end

    def step_in(name)
      @steps.fetch(name).input += 1
    end

    def step_out(name, count = 1)
      @steps.fetch(name).output += count
    end

    def step_filtered(name)
      @steps.fetch(name).filtered += 1
    end

    def step_rejected(name, reason)
      @steps.fetch(name).rejected += 1
      @rejected[reason] += 1
    end

    def step_failed(name, error)
      @steps.fetch(name).failed += 1
      @failed[error.class.name] += 1
    end

    def step_time(name, seconds)
      @steps.fetch(name).time += seconds
    end

    def mark(reason)
      @marked[reason] += 1
    end

    def failed_total
      @failed.values.sum
    end

    def snapshot
      Stats.new(
        read: @read,
        written: @written,
        filtered: @steps.each_value.sum(&:filtered),
        rejected: @rejected.dup,
        marked: @marked.dup,
        failed: @failed.dup,
        steps: @steps.transform_values { |counter| StepStats.new(**counter.to_h) },
        duration: now - @started_at
      )
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

  end
end
