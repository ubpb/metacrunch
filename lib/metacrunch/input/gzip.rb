# frozen_string_literal: true

require "zlib"

module Metacrunch
  class Input
    # The content of all members of the gzip data in a Stream, as zcat reads
    # it, as the source of another Stream. Internal.
    class Gzip

      # zlib warns under -w when a member is ended in the middle ("attempt
      # to close unfinished zstream; reset forced"). While its thread is in
      # Gzip#finish, this drops just that warning; $VERBOSE, which all
      # threads share, stays as it is.
      module Quiet

        MESSAGE = "attempt to close unfinished zstream"
        KEY = :metacrunch_gzip_finish

        def warn(message, ...)
          return if Thread.current[KEY] && message.include?(MESSAGE)

          super
        end

      end
      Warning.singleton_class.prepend(Quiet)

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
      # what was not read, and without zlib's warning about that (Quiet).
      def finish
        quietly { @gzip.finish } unless @gzip.closed?
      rescue Zlib::Error
        nil
      end

      private

      def quietly
        Thread.current[Quiet::KEY] = true
        yield
      ensure
        Thread.current[Quiet::KEY] = nil
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
