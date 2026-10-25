# frozen_string_literal: true

require "rubygems/package"
require "stringio"

module Metacrunch
  class Input
    # The regular members of the tar archive in a Stream. Uses RubyGems'
    # header parser and entries, but checks what they do not: an archive
    # that ends inside a 512-byte block or inside a member's data is broken.
    # Internal.
    class Tar

      BLOCK = 512
      CHECKSUM = (148...156)

      def self.broken(name, reason) = InputError.new("#{name}: broken tar archive (#{reason})")

      def initialize(stream, name)
        @blocks = Blocks.new(stream)
        @name = name
      end

      # Yields a Stream, the name and the full name of every regular member
      # whose base name does not start with ".". A member the block did not
      # read to its end is read to its end afterwards, to check it. So is
      # what follows the end of the archive, so that a gzip layer around it
      # reaches its footer and checks it.
      def each_member
        until @blocks.eof?
          header = next_header
          break if header.empty?

          entry = Gem::Package::TarReader::Entry.new(header, @blocks)
          full_name = full_name(entry)
          member = Member.new(entry, "#{@name}:#{full_name}")
          yield Stream.new(member), member.name, full_name if document?(entry, full_name)
          member.drain
          entry.close
        end
        check_blocks
        @blocks.drain
      end

      private

      def next_header
        check_blocks
        raw = @blocks.read(BLOCK)
        check_blocks
        header = Gem::Package::TarHeader.from(StringIO.new(raw))
        check_sum(raw, header) unless header.empty?
        header
      rescue Gem::Package::TarInvalidError, ArgumentError => e
        raise Tar.broken(@name, e.message)
      end

      # RubyGems parses the checksum field but does not check it. The sum
      # counts the field as spaces; old tars summed signed bytes.
      def check_sum(raw, header)
        bytes = raw.bytes
        bytes[CHECKSUM] = Array.new(CHECKSUM.size, 32)
        return if [bytes.sum, bytes.sum { it > 127 ? it - 256 : it }].include?(header.checksum)

        raise Tar.broken(@name, "wrong header checksum")
      end

      def full_name(entry)
        name = entry.full_name
        raise Tar.broken(@name, "a member name contains a NUL byte") if name.include?("\0")

        name
      rescue Gem::Package::TarInvalidError => e
        raise Tar.broken(@name, e.message)
      end

      def document?(entry, full_name) = entry.file? && !File.basename(full_name).start_with?(".")

      def check_blocks
        raise Tar.broken(@name, "ends inside a 512-byte block") if @blocks.short?
      end

      # What RubyGems reads a tar archive from: a Stream with a position,
      # noting a read that ended early.
      class Blocks

        attr_reader :pos

        def initialize(stream)
          @stream = stream
          @pos = 0
          @short = false
        end

        def short? = @short

        def eof? = @stream.eof?

        def read(length = nil)
          data = @stream.read(length)
          @short = true if length&.positive? && (data.nil? || data.bytesize < length)
          @pos += data.bytesize if data
          data
        end

        def readpartial(length, outbuf = nil)
          data = @stream.readpartial(length, outbuf)
          @pos += data.bytesize
          data
        end

        # Reads the rest of the stream, to its end.
        def drain
          loop { readpartial(Stream::BLOCK) }
        rescue EOFError
          nil
        end

      end

      # A member's data, as the source of a Stream: raises InputError where
      # the archive ends before the data does.
      class Member

        attr_reader :name

        def initialize(entry, name)
          @entry = entry
          @name = name
        end

        def readpartial(length)
          raise EOFError, "end of member reached" if @entry.eof?

          @entry.readpartial(length)
        rescue EOFError
          raise if @entry.eof?

          raise Tar.broken(@name, "ends inside the member's data")
        end

        # Reads the rest of the member, to check it.
        def drain
          loop { readpartial(Stream::BLOCK) }
        rescue EOFError
          nil
        end

      end

    end
  end
end
