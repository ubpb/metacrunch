# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # Messages between the parent and a worker: the size of the payload as
      # 4 bytes in network order, then the payload, a Marshal dump.
      module Frame

        HEADER = "N"
        HEADER_SIZE = 4

        # The largest payload the 4-byte header can describe.
        MAX_SIZE = (2**32) - 1

        # A frame that ends early: its writer ended while writing it.
        class Truncated < Error; end

        module_function

        # Writes data, a String from Marshal.dump, as one frame. Raises Error
        # for 4 GiB or more, which the header cannot describe.
        def write(io, data)
          size = data.bytesize
          if size > MAX_SIZE
            raise Error, "a batch of #{size} bytes is too large to send between processes (at most 4 GiB)"
          end

          io.write([size].pack(HEADER), data)
        end

        # Reads one frame and returns its payload, loaded; nil at the end of
        # the input. Frames come only from this process or its own forked
        # workers, so loading them is safe.
        def read(io)
          header = io.read(HEADER_SIZE)
          return if header.nil?

          size = header.bytesize == HEADER_SIZE ? header.unpack1(HEADER) : nil
          data = size && io.read(size)
          raise Truncated, "the frame ended early" unless data && data.bytesize == size

          Marshal.load(data) # rubocop:disable Security/MarshalLoad
        end

      end
    end
  end
end
