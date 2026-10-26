# frozen_string_literal: true

require "json"

module Metacrunch
  # A source and sinks for JSON Lines: one JSON value per line. The reader
  # takes what Input takes (paths, "-" for stdin, IOs or an Array of them;
  # gzip and tar are unpacked whatever their names), the writers what
  # Output takes (paths, ".gz" compressed, "-" for stdout, IOs). IO objects
  # are never closed.
  module JsonLines

    # Source: yields every line parsed with JSON.parse. A line that is not
    # valid JSON (or not valid UTF-8, or has duplicate keys) is yielded as
    # InvalidRecord, so the job's failure policy decides. Blank lines and byte
    # order marks (also of concatenated files) are skipped.
    class Reader

      BOM = "\uFEFF"
      BLANK = Object.new.freeze
      private_constant :BLANK

      def initialize(targets)
        @input = Input.new(targets)
      end

      # Without a block an Enumerator.
      def each
        return enum_for(:each) unless block_given?

        @input.each_document do |stream, _name|
          stream.each_line do |line|
            line.force_encoding(Encoding::UTF_8)
            line.delete_prefix!(BOM)
            record = parse(line)
            yield record unless record.equal?(BLANK)
          end
        end
      end

      # The share of the input read so far; see Input#progress.
      def progress = @input.progress

      private

      # json accepts invalid UTF-8 inside strings, so the encoding is
      # checked first; a writer would refuse such a record later. Duplicate
      # keys are refused also by the json 2 that comes with Ruby 4.0, which
      # keeps the last one by default.
      def parse(line)
        unless line.valid_encoding?
          return InvalidRecord.new(raw: line.chomp, error: JSON::ParserError.new("invalid UTF-8"))
        end

        JSON.parse(line, allow_duplicate_key: false)
      rescue JSON::ParserError => e
        line.b.strip.empty? ? BLANK : InvalidRecord.new(raw: line.chomp, error: e)
      end

    end

    # Sink: writes every record as one line of JSON. Values that are not
    # JSON types (objects, Time, NaN) are refused instead of written as their
    # to_s. A closed pipe (e.g. `| head`) ends the run like SIGPIPE; see
    # Output.
    class Writer

      def initialize(target)
        @output = Output.new(target)
      end

      def open(_context)
        @output.open
      end

      def write(record, ctx)
        @output.write(line(record, ctx))
      end

      def write_batch(records, ctxs)
        @output.write(records.zip(ctxs).map { |record, ctx| line(record, ctx) }.join)
      end

      def close
        @output.close
      end

      private

      def line(record, ctx)
        "#{JSON.generate(record, strict: true)}\n"
      rescue JSON::GeneratorError => e
        raise Error, "record at position #{ctx.position} is not JSON (#{record.class}): #{e.message}"
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
