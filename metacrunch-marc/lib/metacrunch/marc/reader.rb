# frozen_string_literal: true

require "metacrunch"

module Metacrunch
  module Marc
    # A metacrunch source: reads MARCXML, ISO 2709 and MARC-in-JSON from what
    # Metacrunch::Input reads (paths, "-" for stdin, IOs or an Array of them;
    # gzip and tar are unpacked whatever their names). The format of each
    # document is told by its first bytes (see Formats), so inputs may mix
    # formats. Yields a Record per record, or with parse: false the record
    # as a String in its format, which is cheaper to send to workers. A
    # record that cannot be parsed is yielded as Metacrunch::InvalidRecord; a
    # document in another format raises Metacrunch::InputError.
    class Reader

      ARRAY = "is a JSON array of records; convert it to one record per line first, e.g. " \
              "jq -c '.[]' in.json > out.jsonl"

      # targets: what Metacrunch::Input takes. IOs are never closed.
      def initialize(targets, parse: true, normalize: nil)
        @input = Metacrunch::Input.new(targets)
        Marc.check_normalize(normalize)
        if normalize && !parse
          raise ArgumentError, "normalize: needs parse: true; with parse: false normalize in the step that parses: " \
                               "Metacrunch::Marc.parse(raw, normalize: :nfc)"
        end
        @parse = parse
        @normalize = normalize
      end

      # Without a block an Enumerator.
      def each(&)
        return enum_for(:each) unless block_given?

        @input.each_document do |stream, name|
          format = format(stream, name)
          read(Formats.library(format), stream, &) if format
        end
      end

      # The share of the input read so far; see Metacrunch::Input#progress.
      def progress = @input.progress

      private

      # The format of a document, or nil for one without data. Peeks from one
      # byte on: peek waits until it has as many bytes, and a pipe that
      # pauses after a short first record must not hold it back.
      def format(stream, name)
        format, = Formats.detect(1) { stream.peek(it) }
        case format
        when :none then nil
        when :array then raise Metacrunch::InputError, "#{name}: #{ARRAY}"
        # Detection may have looked at one byte only; the message shows more.
        when :unknown then raise Metacrunch::InputError, "#{name}: is #{Formats.unknown(stream.peek(Formats::WINDOW))}"
        else format
        end
      end

      def read(library, stream)
        library.each_raw(stream) { |raw| yield(@parse ? record(library, raw) : raw) }
      end

      def record(library, raw)
        library.parse(raw, normalize: @normalize)
      rescue ParseError => e
        Metacrunch::InvalidRecord.new(raw:, error: e)
      end

    end
  end
end
