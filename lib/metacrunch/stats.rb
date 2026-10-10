# frozen_string_literal: true

module Metacrunch

  # Counters of one step. time is nil unless the job uses `profile true`.
  StepStats = Data.define(:input, :output, :filtered, :rejected, :failed, :time) do
    def merge(other)
      with(
        input: input + other.input,
        output: output + other.output,
        filtered: filtered + other.filtered,
        rejected: rejected + other.rejected,
        failed: failed + other.failed,
        time: time || other.time ? time.to_f + other.time.to_f : nil
      )
    end
  end

  # Immutable counters of a run. rejected and marked map a reason to a
  # count, failed maps an error class name to a count, steps maps a step
  # name to its StepStats.
  Stats = Data.define(:read, :written, :filtered, :rejected, :marked, :failed, :steps, :duration) do
    def rejected_total = rejected.values.sum
    def marked_total = marked.values.sum
    def failed_total = failed.values.sum

    # Records read per second.
    def rate
      duration.positive? ? read / duration : 0.0
    end

    # Adds another snapshot, e.g. from a worker process. The duration is
    # the longer one, because workers run at the same time.
    def merge(other)
      add = ->(mine, theirs) { mine.merge(theirs) { |_key, a, b| a + b } }
      with(
        read: read + other.read,
        written: written + other.written,
        filtered: filtered + other.filtered,
        rejected: add.call(rejected, other.rejected),
        marked: add.call(marked, other.marked),
        failed: add.call(failed, other.failed),
        steps: steps.merge(other.steps) { |_name, mine, theirs| mine.merge(theirs) },
        duration: [duration, other.duration].max
      )
    end

    def to_h
      super.merge(rate:, steps: steps.transform_values(&:to_h))
    end

    def summary
      counts = ->(hash) { hash.map { |key, count| "#{key}: #{count}" }.join(", ") }
      parts = ["read #{read}", "written #{written}"]
      parts << "filtered #{filtered}" if filtered.positive?
      parts << "rejected #{rejected_total} (#{counts.call(rejected)})" if rejected_total.positive?
      parts << "marked #{marked_total} (#{counts.call(marked)})" if marked_total.positive?
      parts << "failed #{failed_total} (#{counts.call(failed)})" if failed_total.positive?
      "#{parts.join(", ")} in #{format("%.2f", duration)}s (#{rate.round} records/s)"
    end
  end

end
