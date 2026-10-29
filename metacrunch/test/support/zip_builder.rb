# frozen_string_literal: true

require "zlib"

# Writes ZIP archives byte by byte for the tests, also archives that are
# broken or that only some writers produce.
module ZipBuilder

  MAX16 = 0xFFFF
  MAX32 = 0xFFFF_FFFF
  UTF8 = 0x800
  DESCRIPTOR = 0x8
  DATE = 0x21 # 1980-01-01
  ENTRY = {data: "", method: 8, host: 3, mode: 0o100644, dos: 0, flags: 0, utf8: true, crc: nil, size: nil,
           compressed_size: nil, descriptor: nil, zip64: false, extra: "", local_extra: "", unicode_path: nil,
           local_name: nil, disk: 0}.freeze

  module_function

  # entries: name => data (a String), :directory or :symlink; or an Array
  # of entry Hashes with the keys of ENTRY and name:. prefix: bytes before
  # the archive, whose offsets are not adjusted to them. zip64: Zip64 end
  # records. reverse: the central directory in reverse order. count: the
  # end record's entry count. disk: the end record's disk numbers.
  def build(entries, comment: "", trailing: "", prefix: "", zip64: false, reverse: false, count: nil, disk: 0)
    archive = +"".b
    headers = normalize(entries).map { |entry| local(archive, entry) }
    headers.reverse! if reverse
    directory_offset = archive.bytesize
    headers.each { archive << it }
    directory_size = archive.bytesize - directory_offset
    total = count || headers.size
    archive << zip64_end(total, directory_size, directory_offset, archive.bytesize, disk) if zip64
    archive << end_record(zip64 ? [MAX16, MAX32, MAX32] : [total, directory_size, directory_offset], disk, comment)
    prefix.b + archive + trailing.b
  end

  def normalize(entries)
    return entries.map { ENTRY.merge(it) } if entries.is_a?(Array)

    entries.map do |name, data|
      case data
      when :directory then ENTRY.merge(name:, mode: 0o040755, method: 0)
      when :symlink then ENTRY.merge(name:, data: "a.txt", mode: 0o120777, method: 0)
      else ENTRY.merge(name:, data:)
      end
    end
  end

  # Writes the local header and data of entry to archive and returns its
  # central directory header.
  def local(archive, entry)
    name = entry[:name].b
    data = entry[:data].b
    stored = entry[:method] == 8 ? deflate(data) : data
    crc = entry[:crc] || Zlib.crc32(data)
    size = entry[:size] || data.bytesize
    compressed = entry[:compressed_size] || stored.bytesize
    flags = flags(entry)
    offset = archive.bytesize
    archive << local_header(entry, flags, crc, compressed, size)
    archive << stored
    archive << descriptor(entry, crc, compressed, size) if entry[:descriptor]
    central_header(entry, name, flags, crc, compressed, size, offset)
  end

  # Raw deflate data, as ZIP stores it.
  def deflate(data) = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)

  def flags(entry)
    flags = entry[:flags]
    flags |= DESCRIPTOR if entry[:descriptor]
    name = entry[:name].dup.force_encoding(Encoding::UTF_8)
    flags |= UTF8 if entry[:utf8] && !name.ascii_only? && name.valid_encoding?
    flags
  end

  def local_header(entry, flags, crc, compressed, size)
    name = (entry[:local_name] || entry[:name]).b
    values = entry[:descriptor] ? [0, 0, 0] : [crc, compressed, size]
    extra = entry[:local_extra].b
    if entry[:zip64]
      extra = [1, 16, size, compressed].pack("vvQ<Q<") + extra
      values = [values[0], MAX32, MAX32]
    end
    ["PK\x03\x04".b, entry[:zip64] ? 45 : 20, flags, entry[:method], 0, DATE, *values, name.bytesize,
     extra.bytesize].pack("a4vvvvvVVVvv") + name + extra
  end

  def descriptor(entry, crc, compressed, size)
    signature = entry[:descriptor] == :signed ? "PK\x07\x08".b : "".b
    signature + (entry[:zip64] ? [crc, compressed, size].pack("VQ<Q<") : [crc, compressed, size].pack("VVV"))
  end

  def central_header(entry, name, flags, crc, compressed, size, offset)
    extra = entry[:extra].b
    extra = unicode_path(name, entry[:unicode_path]) + extra if entry[:unicode_path]
    values = [compressed, size, offset]
    if entry[:zip64]
      extra = [1, 24, size, compressed, offset].pack("vvQ<Q<Q<") + extra
      values = [MAX32, MAX32, MAX32]
    end
    compressed, size, offset = values
    external = (entry[:mode] << 16) | entry[:dos]
    ["PK\x01\x02".b, (entry[:host] << 8) | 63, entry[:zip64] ? 45 : 20, flags, entry[:method], 0, DATE, crc,
     compressed, size, name.bytesize, extra.bytesize, 0, entry[:disk], 0, external, offset]
      .pack("a4vvvvvvVVVvvvvvVV") + name + extra
  end

  def unicode_path(name, path)
    data = [1, Zlib.crc32(name)].pack("CV") + path.b
    [0x7075, data.bytesize].pack("vv") + data
  end

  def zip64_end(count, size, offset, record_offset, disk)
    record = ["PK\x06\x06".b, 44, 45, 45, disk, disk, count, count, size, offset].pack("a4Q<vvVVQ<Q<Q<Q<")
    record + ["PK\x06\x07".b, disk, record_offset, 1].pack("a4VQ<V")
  end

  def end_record(values, disk, comment)
    count, size, offset = values
    ["PK\x05\x06".b, disk, disk, count, count, size, offset, comment.bytesize].pack("a4vvvvVVv") + comment.b
  end

end
