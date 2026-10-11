# frozen_string_literal: true

require "json"
require "zlib"

module Metacrunch
  # A source and sinks for JSON Lines: one JSON value per line. Each takes a
  # path, "-" for stdin or stdout, or an IO object; IO objects are never
  # closed. Paths ending in ".gz" are read and written with gzip.
  module JsonLines

    STDIO = "-"
    GZIP = ".gz"

    # Source: yields every line parsed with JSON.parse. A line that is not
    # valid JSON (or not valid UTF-8) is yielded as InvalidRecord, so the
    # job's error policy decides. Blank lines are skipped.
    class Reader

      # How often (in lines) the position in a file is sampled for #progress.
      PROGRESS_EVERY = 1024
      BOM = "﻿"
      BLANK = Object.new.freeze
      private_constant :BLANK

      def initialize(target)
        @target = target
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
            line.delete_prefix!(BOM) if lines == 1
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
      # stdin and IO objects). Files are closed when each ends, also by break.
      def with_input(&)
        return yield($stdin, nil) if @target == STDIO
        return yield(@target, nil) unless @target.is_a?(String)

        File.open(@target, "rb") do |file|
          @size = file.size
          @done = 0
          @target.end_with?(GZIP) ? with_gzip(file, &) : yield(file, file)
          @done = @size
        end
      end

      def with_gzip(file)
        gzip = Zlib::GzipReader.new(file)
        begin
          yield gzip, file
        ensure
          gzip.finish
        end
      end

    end

  end
end
