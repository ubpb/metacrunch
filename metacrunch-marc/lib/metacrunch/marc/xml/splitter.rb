# frozen_string_literal: true

module Metacrunch
  module Marc
    module Xml
      # Cuts MARCXML into record strings without parsing it (Xml.each_raw).
      # A record runs from a record start tag, with any prefix, to the next end
      # tag with the same prefix, so concatenated documents with different
      # prefixes work. An end tag inside CDATA or a comment cuts a record
      # there; a record cut off by the end of the input is yielded as it is.
      # Searches go on where they stopped, so a large record costs time in
      # proportion to its size. Internal.
      class Splitter

        CHUNK_SIZE = 65_536

        # Bytes kept while no start tag is found, for a tag cut by a chunk
        # boundary.
        KEEP = 256

        START = %r{<(?:([A-Za-z_][\w.-]*):)?record[\s>/]}n

        SLASH = "/".ord

        def initialize(input)
          @input = input.is_a?(String) ? StringSource.new(input) : input
          @buffer = String.new(encoding: Encoding::BINARY)
          # Where the unused input starts; once a record start tag is found,
          # where the record starts.
          @position = 0
          # The end tag of the record at @position, nil until its start tag
          # is found.
          @end_tag = nil
          # The end of its start tag, nil until found.
          @open_end = nil
          # Where the next search for > or the end tag goes on.
          @scan = 0
        end

        def each
          loop do
            if (xml = take)
              yield xml
            elsif !read_more?
              break
            end
          end
          rest = remainder
          yield rest if rest
        end

        private

        # The next whole record in the buffer, or nil.
        def take
          return unless started?

          @open_end ||= find_open_end
          return unless @open_end
          return finish(@open_end + 1) if @buffer.getbyte(@open_end - 1) == SLASH

          close = @buffer.index(@end_tag, [@scan, @open_end].max)
          if close
            finish(close + @end_tag.bytesize)
          else
            @scan = [@buffer.bytesize - @end_tag.bytesize + 1, @open_end].max
            nil
          end
        end

        # Finds the next record start tag and takes its end tag from its
        # prefix; false until one is in the buffer.
        def started?
          return true if @end_tag

          match = START.match(@buffer, @position)
          unless match
            @position = [@position, @buffer.bytesize - KEEP].max
            return false
          end

          @position = match.begin(0)
          @end_tag = "</#{"#{match[1]}:" if match[1]}record>".b
          @scan = match.end(0) - 1
          true
        end

        def find_open_end
          found = @buffer.index(">", @scan)
          @scan = @buffer.bytesize unless found
          found
        end

        def finish(to)
          xml = slice(@position, to)
          @end_tag = nil
          @open_end = nil
          xml
        end

        # The rest of the input from a record start tag on, at its end: a
        # record the input cut off, which fails when it is parsed. nil if
        # there is none.
        def remainder
          @end_tag && slice(@position, @buffer.bytesize)
        end

        def slice(from, to)
          @position = to
          @buffer.byteslice(from, to - from).force_encoding(Encoding::UTF_8)
        end

        # Appends the next chunk; false at the end of the input. What was
        # taken is dropped only once it is more than a chunk, so a large
        # record is not copied again with every chunk.
        def read_more?
          chunk = read
          return false unless chunk

          compact if @position > CHUNK_SIZE
          @buffer << chunk.b
          true
        end

        def compact
          @buffer = @buffer.byteslice(@position..)
          @scan = [@scan - @position, 0].max
          @open_end -= @position if @open_end
          @position = 0
        end

        def read
          chunk = @input.respond_to?(:readpartial) ? @input.readpartial(CHUNK_SIZE) : @input.read(CHUNK_SIZE)
          chunk unless chunk.nil? || chunk.empty?
        rescue EOFError
          nil
        end

      end
    end
  end
end
