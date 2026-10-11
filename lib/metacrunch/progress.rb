# frozen_string_literal: true

require "io/console"

module Metacrunch
  # Shows the progress of a run on stderr; an Engine monitor (start, stop).
  # In :line mode (stderr is a terminal) it redraws one status line; in :log
  # mode it writes a log line every 10 seconds, also with -q, because it was
  # asked for. A background thread reads the live counters, so the engine
  # does no extra work per record.
  class Progress

    SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze
    BAR_WIDTH = 20
    # Seconds the rate is averaged over.
    RATE_WINDOW = 5.0
    INTERVALS = {line: 0.25, log: 10.0}.freeze

    # stderr shared by the logger and the status line. Each log write first
    # clears the status line; the next tick draws it again.
    class Output

      CLEAR = "\r\e[2K"

      def initialize(io)
        @io = io
        @mutex = Mutex.new
        @status = false
      end

      # For Logger, which needs write and close.
      def write(*strings)
        @mutex.synchronize do
          clear_line
          @io.write(*strings)
        end
      end

      def close = nil

      # The flag is set first: if writing is interrupted (the thread is
      # killed), clear_status still clears what was written.
      def status(text)
        @mutex.synchronize do
          @status = true
          @io.write(CLEAR, fit(text))
          @io.flush
        end
      end

      def clear_status
        @mutex.synchronize { clear_line }
      end

      private

      def clear_line
        return unless @status

        @io.write(CLEAR)
        @status = false
      end

      # Cuts the text to the terminal width, so it never wraps.
      def fit(text)
        width = terminal_width
        width && text.size >= width ? text[0, width - 1] : text
      end

      # nil if unknown; a terminal without a size reports 0 columns.
      def terminal_width
        return unless @io.respond_to?(:winsize)

        width = @io.winsize[1]
        width if width.positive?
      rescue SystemCallError
        nil
      end

    end

    # output: the Output shared with the logger. clock and thread can be
    # replaced in tests.
    def initialize(output, mode:, interval: INTERVALS.fetch(mode), clock: nil, thread: true)
      @output = output
      @mode = mode
      @interval = interval
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @threaded = thread
      @frame = 0
    end

    def start(live)
      @live = live
      @size = known_size(live.source)
      @started = @clock.call
      @samples = [[@started, 0]]
      @thread = start_thread if @threaded
    end

    def stop
      @thread&.kill&.join
      @thread = nil
      @output.clear_status if @mode == :line
    end

    def tick
      return @output.status(line) if @mode == :line

      @output.write(LOG_FORMATTER.call("INFO", Time.now, nil, line))
    end

    # The status: progress (bar or spinner), elapsed time, ETA and counts.
    def line
      now = @clock.call
      read = @live.read
      [head(now - @started, fraction(read)), counts(read, rate(now, read))].join("  ")
    end

    private

    # Draws until stopped. An error in the display (e.g. from a source's
    # progress) ends the display, never the run.
    def start_thread
      Thread.new do
        Thread.current.report_on_exception = false
        loop do
          sleep(@interval)
          tick
        end
      rescue StandardError
        nil
      end
    end

    # Read once, on the run's thread: a source's size may be expensive or
    # unsafe to call while the source is read. count is never called: it
    # would iterate.
    def known_size(source)
      size = source.size if source.respond_to?(:size)
      size if size.is_a?(Integer) && size.positive?
    rescue StandardError
      nil
    end

    def head(elapsed, done)
      percent = done && "#{(done * 100).floor}%"
      eta = done&.positive? && done < 1 ? "ETA #{duration(elapsed * (1 - done) / done)}" : nil
      [marker(done), percent, duration(elapsed), eta].compact.join(" ")
    end

    def marker(done)
      return "progress" if @mode == :log

      done ? bar(done) : spinner
    end

    def counts(read, rate)
      parts = ["read #{number(read)} (#{number(rate)}/s)", "written #{number(@live.written)}"]
      {"filtered" => @live.filtered, "rejected" => @live.rejected, "failed" => @live.failed}.each do |label, count|
        parts << "#{label} #{number(count)}" if count.positive?
      end
      parts.join("  ")
    end

    # Records per second over the last RATE_WINDOW seconds: the oldest kept
    # sample is the newest one that is at least that old.
    def rate(now, read)
      @samples << [now, read]
      @samples.shift while @samples.size > 2 && now - @samples[1][0] >= RATE_WINDOW
      first_time, first_read = @samples.first
      span = now - first_time
      span.positive? ? (read - first_read) / span : 0.0
    end

    # The share of the input done, from the source's progress or size or
    # the limit; nil if unknown.
    def fraction(read)
      source = @live.source
      limit = @live.limit
      candidates = [source.respond_to?(:progress) ? source.progress : nil]
      candidates << read.fdiv(@size) if @size
      candidates << read.fdiv(limit) if limit
      done = candidates.compact.max
      done && [done, 1.0].min
    end

    def number(value)
      return format("%.2fM", value / 1_000_000.0) if value >= 1_000_000
      return format("%.1fk", value / 1000.0) if value >= 1000
      return format("%.1f", value) if value.is_a?(Float)

      value.to_s
    end

    def duration(seconds)
      total = seconds.to_i
      format("%<hours>02d:%<minutes>02d:%<seconds>02d", hours: total / 3600, minutes: total % 3600 / 60,
                                                        seconds: total % 60)
    end

    def bar(done)
      filled = (done * BAR_WIDTH).floor
      ("━" * filled) + ("─" * (BAR_WIDTH - filled))
    end

    def spinner
      SPINNER[(@frame += 1) % SPINNER.size]
    end

  end
end
