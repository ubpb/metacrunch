# frozen_string_literal: true

module Metacrunch
  module Xlsx
    # A deflated entry of a ZipKit::Streamer, written in pieces like the
    # Writable of ZipKit's write_deflated_file, but safe against signals:
    # when a signal (Ctrl-C) wakes the thread inside zlib, Zlib::Deflate
    # raises Zlib::BufError although it keeps the input it did not take, and
    # ZipKit's writer then leaves that piece out of the CRC. Here the CRC and
    # the size are counted before deflating, and Zlib::BufError is ignored.
    # Internal.
    class Entry

      def initialize(zip, name)
        @zip = zip
        @zip.add_deflated_entry(filename: name, use_data_descriptor: true)
        @deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
        @crc = Zlib.crc32
        @size = 0
      end

      def <<(data)
        @crc = Zlib.crc32(data, @crc)
        @size += data.bytesize
        deflate { @deflater.deflate(data) { @zip << it } }
        self
      end

      # Writes the rest of the compressed data and the data descriptor.
      def close
        deflate { @zip << @deflater.finish } until @deflater.finished?
        @zip.update_last_entry_and_write_data_descriptor(crc32: @crc, compressed_size: @deflater.total_out,
                                                         uncompressed_size: @size)
      ensure
        @deflater.close
      end

      private

      # The next call goes on with the input that zlib kept.
      def deflate
        yield
      rescue Zlib::BufError
        nil
      end

    end
  end
end
