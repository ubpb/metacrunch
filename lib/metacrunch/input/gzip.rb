# frozen_string_literal: true

require "zlib"

module Metacrunch
  class Input
    # The content of all members of the gzip data in a Stream, as zcat reads
    # it, as the source of another Stream. Internal.
    class Gzip

      def initialize(stream, name)
        @stream = stream
        @name = name
        @gzip = member
      end

      # Raises InputError for broken or truncated data (also when only the
      # footer is missing) and for data after the last member.
      def readpartial(length)
        loop do
          return @gzip.readpartial(length)
        rescue EOFError
          raise unless next_member?
        rescue Zlib::Error => e
          raise InputError, "#{@name}: broken gzip data (#{e.message})"
        end
      end

      # Ends the gzip layer without closing the stream and without checking
      # what was not read. Ending a member in the middle makes zlib warn
      # under -w ("attempt to close unfinished zstream"), so warnings are
      # off meanwhile.
      def finish
        quietly { @gzip.finish } unless @gzip.closed?
      rescue Zlib::Error
        nil
      end

      private

      def quietly
        verbose = $VERBOSE
        $VERBOSE = nil
        yield
      ensure
        $VERBOSE = verbose
      end

      def member
        Zlib::GzipReader.new(@stream)
      rescue Zlib::Error => e
        raise InputError, "#{@name}: broken gzip data (#{e.message})"
      end

      # After a member: puts the bytes it did not use back; true if another
      # member follows.
      def next_member?
        unused = @gzip.unused
        @gzip.finish
        @stream.unread(unused) if unused
        return false if @stream.eof?
        raise InputError, "#{@name}: data after the end of the gzip data" unless @stream.peek(3) == Formats::GZIP

        @gzip = member
        true
      end

    end
  end
end
