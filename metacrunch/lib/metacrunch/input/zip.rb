# frozen_string_literal: true

require "zlib"

module Metacrunch
  class Input
    # A ZIP archive in a seekable IO: its entries, in the order of the
    # central directory. Raises InputError for a broken archive. As strict
    # as gzip and tar where data could come out wrong, as tolerant as
    # unzip, Python, Go and libarchive elsewhere (bytes after the end
    # record, padding in extra fields, more than 65,535 entries without
    # Zip64). Internal; metacrunch's own gems may use it, e.g. to read the
    # parts of a workbook.
    class Zip

      END_RECORD = "PK\x05\x06".b
      ZIP64_LOCATOR = "PK\x06\x07".b
      ZIP64_END = "PK\x06\x06".b
      CENTRAL = "PK\x01\x02".b
      END_SIZE = 22
      LOCATOR_SIZE = 20
      ZIP64_END_SIZE = 56
      CENTRAL_SIZE = 46
      LOCAL_SIZE = 30
      MAX_COMMENT = 0xFFFF
      MAX16 = 0xFFFF
      MAX32 = 0xFFFF_FFFF
      ZIP64_EXTRA = 0x0001
      UNICODE_PATH = 0x7075
      UTF8 = 0x800
      UNIX = 3
      S_IFMT = 0o170000
      S_IFDIR = 0o040000
      S_IFLNK = 0o120000
      DOS_DIRECTORY = 0x10

      # An entry of the central directory. host: the system that wrote it
      # (3 for Unix); external: its attributes (the Unix mode in the upper
      # 16 bits, MS-DOS attributes in the lower).
      Entry = Data.define(:name, :flags, :compression, :crc, :compressed_size, :size, :header_offset, :host,
                          :external) do
        # A Unix mode with a file type decides; else, as from MS-DOS and
        # Windows, the directory attribute.
        def directory?
          return true if name.end_with?("/")
          return type == S_IFDIR if unix_type?

          external.anybits?(DOS_DIRECTORY)
        end

        def link? = host == UNIX && type == S_IFLNK

        # Traditional or strong encryption, or WinZip AES (method 99).
        def encrypted? = flags.anybits?(0x41) || compression == 99

        # Not a directory or a link, and no base name starting with ".",
        # as for tar members; a FIFO (Info-ZIP's entry for stdin) and a
        # mode without a type are documents.
        def document? = !directory? && !link? && !name.rpartition("/").last.start_with?(".")

        private

        def type = (external >> 16) & S_IFMT

        def unix_type? = host == UNIX && !type.zero?
      end

      # Where the central directory is, from the end records.
      Directory = Data.define(:count, :size, :offset, :end_offset, :zip64, :one_disk)

      # A candidate end record that does not lead to a directory. Internal.
      class Mismatch < StandardError; end

      def self.broken(name, reason) = InputError.new("#{name}: broken zip archive (#{reason})")

      # io: seekable (seek, read, size); start: the archive's offset in io;
      # position: called with the offset in the archive up to which the
      # data of entries has been read, for progress.
      def initialize(io, name, start: 0, position: nil)
        @io = io
        @name = name
        @start = start
        @position = position
        @size = io.size - start
        @entries = read_directory.freeze
      end

      attr_reader :entries

      # The first entry of that name, or nil.
      def entry(name) = @entries.find { it.name == name }

      private

      def broken(reason) = Zip.broken(@name, reason)

      # Callers keep offset and length within the archive; an IO that
      # gives less than its size said (a file that shrank) ends early.
      def read_at(offset, length)
        @io.seek(@start + offset)
        data = @io.read(length)
        raise broken("ends early") unless data && data.bytesize == length

        data.b
      end

      # The end record is the last one in the tail whose comment fits and
      # whose directory lies where it says: that skips an end record inside
      # the comment. The first candidate's problem is the one reported.
      def read_directory
        failure = nil
        each_end_record do |offset, record|
          return parse(locate(offset, record))
        rescue Mismatch => e
          failure ||= e.message
        end
        raise broken(failure || "no end of central directory record")
      end

      def each_end_record
        tail_offset = [@size - END_SIZE - MAX_COMMENT, 0].max
        tail = read_at(tail_offset, @size - tail_offset)
        index = tail.bytesize - END_SIZE
        while index >= 0 && (index = tail.rindex(END_RECORD, index))
          record = tail.byteslice(index, END_SIZE)
          yield tail_offset + index, record if record.unpack1("v", offset: 20) <= tail.bytesize - index - END_SIZE
          index -= 1
        end
      end

      def locate(offset, record)
        disk, directory_disk, disk_count, count, size, directory_offset = record.unpack("x4vvvvVV")
        directory = zip64(offset)
        unless directory
          if count == MAX16 || [size, directory_offset].include?(MAX32)
            raise Mismatch, "the Zip64 end record is missing"
          end

          directory = Directory.new(count:, size:, offset: directory_offset, end_offset: offset, zip64: false,
                                    one_disk: disk.zero? && directory_disk.zero? && disk_count == count)
        end
        unless directory.offset + directory.size == directory.end_offset
          raise Mismatch, "the central directory does not end where the end record says"
        end
        raise split unless directory.one_disk

        directory
      end

      # The directory from the Zip64 end record, or nil without a locator
      # right before the end record.
      def zip64(end_offset)
        return if end_offset < LOCATOR_SIZE

        locator_offset = end_offset - LOCATOR_SIZE
        locator = read_at(locator_offset, LOCATOR_SIZE)
        return unless locator.start_with?(ZIP64_LOCATOR)

        locator_disk, offset, disks = locator.unpack("x4VQ<V")
        raise Mismatch, "broken Zip64 end record" if offset + ZIP64_END_SIZE > locator_offset

        record = read_at(offset, ZIP64_END_SIZE)
        size, _made, _needed, disk, directory_disk, disk_count, count, directory_size, directory_offset =
          record.unpack("x4Q<vvVVQ<Q<Q<Q<")
        unless record.start_with?(ZIP64_END) && offset + 12 + size == locator_offset
          raise Mismatch, "broken Zip64 end record"
        end

        Directory.new(count:, size: directory_size, offset: directory_offset, end_offset: offset, zip64: true,
                      one_disk: [locator_disk, disk, directory_disk].all?(&:zero?) && disks <= 1 &&
                                disk_count == count)
      end

      def split = InputError.new(Formats::SPLIT.message(@name, nil))

      def parse(directory)
        data = read_at(directory.offset, directory.size)
        entries = []
        position = 0
        position = parse_entry(data, position, entries) while position < data.bytesize
        check_count(entries, directory)
        check_overlaps(entries)
        entries
      end

      # Appends the entry at position of data and returns where the next
      # one starts.
      def parse_entry(data, position, entries)
        unless position + CENTRAL_SIZE <= data.bytesize && data.byteslice(position, 4) == CENTRAL
          raise broken("broken central directory entry")
        end

        made_by, _needed, flags, compression, _time, _date, crc, compressed, size, name_length, extra_length,
          comment_length, disk, _internal, external, header = data.unpack("x4vvvvvvVVVvvvvvVV", offset: position)
        name_at = position + CENTRAL_SIZE
        position = name_at + name_length + extra_length + comment_length
        raise broken("broken central directory entry") if position > data.bytesize

        raw_name = data.byteslice(name_at, name_length)
        fields = extra_fields(data.byteslice(name_at + name_length, extra_length))
        size, compressed, header, disk = zip64_values(fields[ZIP64_EXTRA], [size, compressed, header, disk])
        raise split unless disk.zero?

        entries << Entry.new(name: name(raw_name, flags, fields[UNICODE_PATH]), flags:, compression:, crc:,
                             compressed_size: compressed, size:, header_offset: header, host: made_by >> 8,
                             external:)
        position
      end

      # id => data. A rest too short for a field (padding, as zipalign
      # writes it) is ignored.
      def extra_fields(extra)
        fields = {}
        position = 0
        while position + 4 <= extra.bytesize
          id, length = extra.unpack("vv", offset: position)
          break if position + 4 + length > extra.bytesize

          fields[id] ||= extra.byteslice(position + 4, length)
          position += 4 + length
        end
        fields
      end

      # The Zip64 extra field holds, in this order, the values that are at
      # their maximum in the entry: sizes and offset (8 bytes each), disk
      # (4 bytes).
      def zip64_values(field, values)
        position = 0
        values.each_with_index.map do |value, index|
          next value unless value == (index == 3 ? MAX16 : MAX32)

          width = index == 3 ? 4 : 8
          raise broken("an entry lacks its Zip64 extra field") unless field && position + width <= field.bytesize

          position += width
          field.unpack1(width == 8 ? "Q<" : "V", offset: position - width)
        end
      end

      # UTF-8 if the flag says so; else Info-ZIP's Unicode Path field if it
      # belongs to this name; else the bytes if they are UTF-8; else CP437,
      # the code page of MS-DOS.
      def name(raw, flags, unicode_path)
        raise broken("a name contains a NUL byte") if raw.include?("\0")
        return utf8(raw) if flags.anybits?(UTF8)
        return utf8(unicode_path.byteslice(5..)) if unicode_path?(unicode_path, raw)

        name = raw.dup.force_encoding(Encoding::UTF_8)
        name.valid_encoding? ? name : raw.dup.force_encoding(Encoding::IBM437).encode(Encoding::UTF_8)
      end

      def unicode_path?(field, raw)
        field && field.bytesize > 5 && field.getbyte(0) == 1 && field.unpack1("V", offset: 1) == Zlib.crc32(raw)
      end

      def utf8(bytes) = bytes.dup.force_encoding(Encoding::UTF_8).scrub

      def check_count(entries, directory)
        matches = directory.zip64 ? entries.size == directory.count : entries.size % (MAX16 + 1) == directory.count
        return if matches

        raise broken("the central directory has #{entries.size} entries, the end record says #{directory.count}")
      end

      # Entries that share data, as in some zip bombs.
      def check_overlaps(entries)
        entries.sort_by(&:header_offset).each_cons(2) do |a, b|
          raise broken("entries overlap") if a.header_offset + LOCAL_SIZE + a.compressed_size > b.header_offset
        end
      end

    end
  end
end
