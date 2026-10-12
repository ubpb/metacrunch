# frozen_string_literal: true

require "metacrunch"
require "zlib"

module Metacrunch
  module Marcxml
    # A metacrunch sink: writes Records as one MARCXML <collection> to a
    # file (.gz compressed), stdout ("-") or an IO. close writes the end of
    # the collection, also after an aborted run, so the output stays
    # well-formed.
    class Writer

      STDIO = "-"
      GZIP = ".gz"
      HEADER = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<collection xmlns=\"#{NAMESPACE}\">\n".freeze
      FOOTER = "</collection>\n"

      def initialize(target)
        @target = target.is_a?(Pathname) ? target.to_s : target
        @io = nil
        @own = false
        @broken = false
      end

      def open(_context)
        @io, @own = output
        emit(HEADER)
      end

      def write(record, ctx)
        emit(xml(record, ctx))
      end

      def write_batch(records, ctxs)
        emit(records.zip(ctxs).map { |record, ctx| xml(record, ctx) }.join)
      end

      def close
        io = @io
        @io = nil
        return unless io

        guard { io.write(FOOTER) }
        guard { @own ? io.close : io.flush }
      ensure
        discard(io) if @own && io && !io.closed?
      end

      private

      def xml(record, ctx)
        unless record.is_a?(Record)
          raise Metacrunch::Error,
                "record at position #{ctx.position} is not a Metacrunch::Marcxml::Record (#{record.class})"
        end

        record.to_xml(namespace: false).each_line.map { "  #{it}" }.join
      rescue SerializeError => e
        raise Metacrunch::Error, "record at position #{ctx.position} cannot be written as MARCXML: #{e.message}"
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

      # Closes a file after a broken pipe; its buffer can no longer be
      # written.
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
  end
end
