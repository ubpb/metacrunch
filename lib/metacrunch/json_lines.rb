# frozen_string_literal: true

require "json"
require "zlib"

module Metacrunch
  # A source and sinks for JSON Lines: one JSON value per line. Each takes a
  # path (String or Pathname), "-" for stdin or stdout, or an IO object; IO
  # objects are never closed. Paths ending in ".gz" are read and written with
  # gzip.
  module JsonLines

    STDIO = "-"
    GZIP = ".gz"

    # Source: yields every line parsed with JSON.parse. A line that is not
    # valid JSON (or not valid UTF-8, or has duplicate keys) is yielded as
    # InvalidRecord, so the job's failure policy decides. Blank lines and byte
    # order marks (also of concatenated files) are skipped.
    class Reader

      # How often (in lines) the position in a file is sampled for #progress.
      PROGRESS_EVERY = 1024
      BOM = "\uFEFF"
      BLANK = Object.new.freeze
      private_constant :BLANK

      def initialize(target)
        @target = target.is_a?(Pathname) ? target.to_s : target
        @size = nil
        @done = 0
      end

      def each
        with_input do |io, file|
          lines = 0
          io.each_line do |line|
            lines += 1
            @done = file.pos if file && (lines % PROGRESS_EVERY).zero?
            line.force_encoding(Encoding::UTF_8)
            line.delete_prefix!(BOM)
            record = parse(line)
            yield record unless record.equal?(BLANK)
          end
        end
      end

      # The share of the file read so far, from 0.0 to 1.0; nil for stdin,
      # IO objects and before reading. For gzip files it is the position in
      # the compressed file.
      def progress
        size = @size
        return unless size
        return 1.0 if size.zero?

        [@done.fdiv(size), 1.0].min
      end

      private

      # json accepts invalid UTF-8 inside strings, so the encoding is
      # checked first; a writer would refuse such a record later.
      def parse(line)
        unless line.valid_encoding?
          return InvalidRecord.new(raw: line.chomp, error: JSON::ParserError.new("invalid UTF-8"))
        end

        JSON.parse(line)
      rescue JSON::ParserError => e
        line.b.strip.empty? ? BLANK : InvalidRecord.new(raw: line.chomp, error: e)
      end

      # Yields the IO to read lines from and the File for progress (nil for
      # stdin, IO objects, pipes and FIFOs, which have no size or position).
      # Files are closed when each ends, also by break.
      def with_input
        return yield($stdin, nil) if @target == STDIO
        return yield(@target, nil) unless @target.is_a?(String)

        File.open(@target, "rb") do |file|
          regular = file.stat.file?
          @size = regular ? file.size : nil
          @done = 0
          yield @target.end_with?(GZIP) ? GzipMembers.new(file) : file, regular ? file : nil
          @done = @size if regular
        end
      end

    end

    # The lines of all members of a gzip stream, as zcat reads them. Files
    # written with `cat a.gz b.gz` or `gzip >>` have several members.
    class GzipMembers

      def initialize(io)
        @io = io
      end

      def each_line(&)
        loop do
          gzip = Zlib::GzipReader.new(@io)
          begin
            gzip.each_line(&)
            unused = gzip.unused
          ensure
            gzip.finish
          end
          @io.ungetbyte(unused) if unused
          break if @io.eof?
        end
      end

    end
    private_constant :GzipMembers

    # Sink: writes every record as one line of JSON. Values that are not
    # JSON types (objects, Time, NaN) are refused instead of written as their
    # to_s. A closed pipe (EPIPE, e.g. `| head`) ends the run like SIGPIPE:
    # the writer raises SignalException("PIPE") and writes nothing afterwards.
    class Writer

      def initialize(target)
        @target = target.is_a?(Pathname) ? target.to_s : target
        @io = nil
        @own = false
        @broken = false
      end

      def open(_context)
        @io, @own = output
      end

      def write(record, ctx)
        emit(line(record, ctx))
      end

      def write_batch(records, ctxs)
        emit(records.zip(ctxs).map { |record, ctx| line(record, ctx) }.join)
      end

      def close
        io = @io
        @io = nil
        return unless io

        guard { @own ? io.close : io.flush }
      ensure
        discard(io) if @own && io && !io.closed?
      end

      private

      def line(record, ctx)
        "#{JSON.generate(record, strict: true)}\n"
      rescue JSON::GeneratorError => e
        raise Error, "record at position #{ctx.position} is not JSON (#{record.class}): #{e.message}"
      end

      def emit(text)
        guard { @io.write(text) }
      end

      # Turns EPIPE into SIGPIPE, once; afterwards nothing is written.
      def guard
        return if @broken

        yield
      rescue Errno::EPIPE
        @broken = true
        raise SignalException, "PIPE"
      end

      # Closes a file after a broken pipe; its buffer can no longer be written.
      def discard(io)
        io.close
      rescue Errno::EPIPE
        nil
      end

      # [io, own]: own IOs are closed, IOs from outside only flushed.
      def output
        return [$stdout, false] if @target == STDIO
        return [@target, false] unless @target.is_a?(String)
        return [Zlib::GzipWriter.open(@target), true] if @target.end_with?(GZIP)

        [File.open(@target, "w"), true]
      end

    end

    # Sink for the rejects and failures roles: writes every record with its
    # context as an envelope (record, id, position, marks, rejection,
    # failure). Values that are not JSON types are written as their inspect
    # string and strings with invalid UTF-8 scrubbed, so diagnostics never
    # stop a run.
    class ContextWriter < Writer

      private

      def line(record, ctx)
        "#{JSON.generate(envelope(record, ctx), strict: true)}\n"
      end

      def envelope(record, ctx)
        plain = record.is_a?(String) || json?(record)
        data = {"record" => plain ? json(record) : record.inspect}
        data["record_class"] = record.class.name unless plain
        data.merge!("id" => json(ctx.id), "position" => ctx.position, "marks" => ctx.marks.map { note(it) })
        data["rejection"] = note(ctx.rejection) if ctx.rejection
        data["failure"] = failure(ctx.failure) if ctx.failure
        data
      end

      def note(entry)
        {"reason" => json(entry.reason), "step" => entry.step, "value" => json(entry.value)}
      end

      def failure(failure)
        error = failure.error
        {"step" => failure.step, "error" => error_class(error), "message" => json(error_message(error))}
      end

      # A WorkerError stands for an exception of a worker; it is written as
      # that exception, as without workers.
      def error_class(error) = error.is_a?(WorkerError) ? error.original_class : error.class.name

      def error_message(error) = error.is_a?(WorkerError) ? error.original_message : error.message

      def json(value)
        value = value.scrub if value.is_a?(String)
        json?(value) ? value : value.inspect
      end

      def json?(value)
        JSON.generate(value, strict: true)
        true
      rescue JSON::GeneratorError
        false
      end

    end

  end
end
