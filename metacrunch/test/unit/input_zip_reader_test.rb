# frozen_string_literal: true

require "test_helper"

class InputZipReaderTest < Minitest::Test

  Zip = Metacrunch::Input::Zip

  def test_entries_in_directory_order
    entries = reader(ZipBuilder.build({"a.txt" => "abc", "d/" => :directory, "d/b.txt" => ""})).entries

    assert_equal ["a.txt", "d/", "d/b.txt"], entries.map(&:name)
    assert_equal [3, 0, 0], entries.map(&:size)
    assert_equal [Zlib.crc32("abc"), 0, 0], entries.map(&:crc)
  end

  def test_empty_archive
    assert_empty reader(ZipBuilder.build({})).entries
  end

  def test_comment_and_trailing_bytes_are_allowed
    [{comment: "c"}, {trailing: "\0" * 189}, {comment: "c", trailing: "junk"}].each do |options|
      assert_equal ["a.txt"], names(ZipBuilder.build({"a.txt" => "a"}, **options))
    end
  end

  def test_a_fake_end_record_in_the_comment_is_skipped
    comment = "PK\x05\x06#{"\0" * 16}\x05\0trick"

    assert_equal ["a.txt"], names(ZipBuilder.build({"a.txt" => "a"}, comment:))
  end

  def test_a_truncated_comment
    archive = ZipBuilder.build({"a.txt" => "a"}, comment: "cc").byteslice(0..-2)

    assert_equal "a.zip: broken zip archive (no end of central directory record)", error(archive)
  end

  # The bytes of an end record in the data before must not take over.
  def test_a_truncated_comment_after_end_record_bytes_in_the_data
    data = "PK\x05\x06#{"\0" * 18}"
    archive = ZipBuilder.build([{name: "a.txt", data:, method: 0}], comment: "cc").byteslice(0..-2)

    assert_equal "a.zip: broken zip archive (no end of central directory record)", error(archive)
  end

  def test_truncated_archives
    archive = ZipBuilder.build({"a.txt" => "a" * 100, "b.txt" => "b" * 100})

    [0, 10, archive.bytesize / 2, archive.bytesize - 1].each do |cut|
      assert error(archive.byteslice(0, cut)).start_with?("a.zip: broken zip archive ("), "cut at #{cut}"
    end
  end

  def test_a_central_directory_out_of_place
    archive = ZipBuilder.build({"a.txt" => "a"}, prefix: "x" * 100)

    assert_equal "a.zip: broken zip archive (the central directory does not end where the end record says)",
                 error(archive)
  end

  def test_zip64
    archive = ZipBuilder.build([{name: "a.txt", data: "abc", zip64: true}, {name: "b.txt", data: "de"}], zip64: true)
    entries = reader(archive).entries
    sizes = entries.to_h { [it.name, it.size] }

    assert_equal({"a.txt" => 3, "b.txt" => 2}, sizes)
    assert_equal 0, entries.first.header_offset
    assert_operator entries.last.header_offset, :>, 0
  end

  def test_a_broken_zip64_end_record
    archive = ZipBuilder.build({"a.txt" => "a"}, zip64: true)
    at = archive.index("PK\x06\x06".b) + 4
    archive[at, 8] = [45].pack("Q<")

    assert_equal "a.zip: broken zip archive (broken Zip64 end record)", error(archive)
  end

  def test_a_zip64_locator_pointing_elsewhere
    archive = ZipBuilder.build({"a.txt" => "a"}, zip64: true)
    at = archive.index("PK\x06\x07".b) + 8
    archive[at, 8] = [archive.bytesize].pack("Q<")

    assert_equal "a.zip: broken zip archive (broken Zip64 end record)", error(archive)
  end

  def test_broken_central_directory_entries
    archive = ZipBuilder.build({"a.txt" => "a", "b.txt" => "b"})
    second = archive.index("PK\x01\x02".b, archive.index("PK\x01\x02".b) + 4)
    wrong_signature = archive.dup.tap { it[second, 4] = "PK\x01\x03".b }
    long_name = archive.dup.tap { it[second + 28, 2] = [500].pack("v") }

    assert_equal "a.zip: broken zip archive (broken central directory entry)", error(wrong_signature)
    assert_equal "a.zip: broken zip archive (broken central directory entry)", error(long_name)
  end

  def test_a_disk_number_in_the_zip64_extra_field
    entry = {name: "a.txt", data: "a", disk: 0xFFFF}

    assert_equal ["a.txt"], names(ZipBuilder.build([entry.merge(extra: [1, 4, 0].pack("vvV"))]))
    assert_equal Metacrunch::Input::Formats::SPLIT.message("a.zip", nil),
                 error(ZipBuilder.build([entry.merge(extra: [1, 4, 1].pack("vvV"))]))
  end

  # A file that shrinks while it is read: size says more than read gives.
  def test_an_io_shorter_than_its_size
    io = StringIO.new(ZipBuilder.build({"a.txt" => "a"}))
    def io.size = super + 10

    error = assert_raises(Metacrunch::InputError) { Zip.new(io, "a.zip") }

    assert_equal "a.zip: broken zip archive (ends early)", error.message
  end

  # A maxed value that leads nowhere needs the Zip64 end record.
  # A failing disk or network mount, as Raw names it for gzip and tar.
  def test_a_read_error_names_the_archive
    io = StringIO.new(ZipBuilder.build({"a.txt" => "a"}))
    def io.read(*) = raise(Errno::EIO)

    error = assert_raises(Metacrunch::InputError) { Zip.new(io, "a.zip") }

    assert_equal "a.zip: input/output error", error.message
  end

  def test_maxed_values_without_zip64
    archive = ZipBuilder.build({"a.txt" => "a"})
    archive[archive.rindex("PK\x05\x06".b) + 16, 4] = [0xFFFF_FFFF].pack("V")

    assert_equal "a.zip: broken zip archive (the Zip64 end record is missing)", error(archive)

    archive = ZipBuilder.build([{name: "a.txt", data: "a", size: 0xFFFF_FFFF}])

    assert_equal "a.zip: broken zip archive (an entry lacks its Zip64 extra field)", error(archive)
  end

  # Python writes Zip64 only for more than 65,535 entries: 65,535 is a
  # count of 0xFFFF in the classic end record, and a true one.
  def test_exactly_65535_entries_without_zip64
    entries = Array.new(65_535) { {name: "f#{it}", method: 0} }

    assert_equal 65_535, reader(ZipBuilder.build(entries)).entries.size
  end

  def test_more_than_65535_entries_without_zip64
    entries = Array.new(65_537) { {name: "f#{it}", method: 0} }

    assert_equal 65_537, reader(ZipBuilder.build(entries, count: 1)).entries.size
  end

  def test_a_wrong_count
    archive = ZipBuilder.build({"a.txt" => "a", "b.txt" => "b"}, count: 3)

    assert_equal "a.zip: broken zip archive (the central directory has 2 entries, the end record says 3)",
                 error(archive)
  end

  def test_split_archives
    message = Metacrunch::Input::Formats::SPLIT.message("a.zip", nil)

    assert_equal message, error(ZipBuilder.build({"a.txt" => "a"}, disk: 1))
    assert_equal message, error(ZipBuilder.build([{name: "a.txt", data: "a", disk: 1}]))
  end

  def test_utf8_names_and_unicode_path_fields
    wrong = [1, 0].pack("CV") + "Bücher.csv".b
    extra = [0x7075, wrong.bytesize].pack("vv") + wrong

    assert_equal ["Bücher.csv"], names(ZipBuilder.build({"Bücher.csv" => "1"}))
    assert_equal ["Bücher.csv"], names(ZipBuilder.build([{name: "B?cher.csv", unicode_path: "Bücher.csv"}]))
    assert_equal ["B?cher.csv"], names(ZipBuilder.build([{name: "B?cher.csv", extra:}]))
  end

  def test_names_without_the_utf8_flag
    assert_equal ["Bücher.csv"], names(ZipBuilder.build([{name: "Bücher.csv", utf8: false}]))
    assert_equal ["Bücher.csv"], names(ZipBuilder.build([{name: "B\x81cher.csv".b}]))
  end

  def test_a_nul_in_a_name
    assert_equal "a.zip: broken zip archive (a name contains a NUL byte)", error(ZipBuilder.build([{name: "a\0b"}]))
  end

  def test_names_are_utf8
    encodings = reader(ZipBuilder.build([{name: "a.txt"}, {name: "B\x81.txt".b}])).entries.map { it.name.encoding }

    assert_equal [Encoding::UTF_8] * 2, encodings
  end

  def test_directories_and_links
    entries = kinds

    assert_equal ["d/", "e", "f"], entries.select(&:directory?).map(&:name)
    assert_equal ["l"], entries.select(&:link?).map(&:name)
  end

  def test_documents_and_encrypted_entries
    entries = kinds

    assert_equal ["fifo", "plain", "x", "y", "z", "dos.txt"], entries.select(&:document?).map(&:name)
    assert_equal ["x", "y", "z"], entries.select(&:encrypted?).map(&:name)
  end

  def test_extra_padding_is_ignored
    assert_equal ["a.txt"], names(ZipBuilder.build([{name: "a.txt", extra: "\0\0\0"}]))
    assert_equal ["a.txt"], names(ZipBuilder.build([{name: "a.txt", extra: "#{[0xCAFE, 10].pack("vv")}ab"}]))
  end

  def test_directory_order_differs_from_data_order
    assert_equal ["b.txt", "a.txt"], names(ZipBuilder.build({"a.txt" => "a", "b.txt" => "b"}, reverse: true))
  end

  def test_overlapping_entries
    archive = ZipBuilder.build({"a.txt" => "a" * 50, "b.txt" => "b" * 50})
    second = archive.index("PK\x01\x02".b, archive.index("PK\x01\x02".b) + 4)
    archive[second + 42, 4] = [0].pack("V")

    assert_equal "a.zip: broken zip archive (entries overlap)", error(archive)
  end

  def test_entry_finds_the_first_of_a_name
    zip = reader(ZipBuilder.build([{name: "a.txt", data: "1"}, {name: "a.txt", data: "22"}]))

    assert_equal 1, zip.entry("a.txt").size
    assert_nil zip.entry("b.txt")
  end

  def test_an_archive_inside_an_io_starts_at_start
    io = StringIO.new("junk#{ZipBuilder.build({"a.txt" => "a"})}")

    assert_equal ["a.txt"], Zip.new(io, "a.zip", start: 4).entries.map(&:name)
  end

  def test_stored_and_deflated_data
    [0, 8].each do |method|
      zip = reader(ZipBuilder.build([{name: "a.txt", data: "x" * 200_000, method:}]))

      assert_equal "x" * 200_000, read_all(zip, zip.entries.first)
    end
  end

  def test_data_descriptors
    contents = [:signed, :unsigned].map do |descriptor|
      zip = reader(ZipBuilder.build([{name: "a.txt", data: "abc" * 1000, descriptor:}, {name: "b.txt", data: "b"}]))
      zip.entries.map { read_all(zip, it) }
    end

    assert_equal [["abc" * 1000, "b"]] * 2, contents
  end

  def test_data_comes_in_blocks
    data = Random.new(1).bytes(1 << 20)
    zip = reader(ZipBuilder.build([{name: "a.bin", data:}]))
    member = zip.member(zip.entries.first)
    sizes = []
    begin
      loop { sizes << member.readpartial(10_000_000).bytesize }
    rescue EOFError
      nil
    end

    assert_equal data.bytesize, sizes.sum
    assert_operator sizes.max, :<=, 65_536
  end

  def test_a_bomb_comes_in_blocks_too
    zip = reader(ZipBuilder.build([{name: "zeros", data: "\0" * (32 << 20)}]))
    member = zip.member(zip.entries.first)

    assert_equal 65_536, member.readpartial(10_000_000).bytesize
  end

  # Zeros inflate a thousandfold: the inflater must not get much of them at
  # once, or memory grows with the entry.
  def test_inflating_a_bomb_holds_little_at_a_time
    assert_operator largest_inflate("\0" * (32 << 20)), :<=, 1_100_000
  end

  # After incompressible data the inflater gets its most input; zeros that
  # follow then give the most output at once (MAX_INPUT times about 1,032).
  def test_a_bomb_after_incompressible_data_holds_little_at_a_time_too
    assert_operator largest_inflate(Random.new(6).bytes(1 << 20) + ("\0" * (32 << 20))), :<=, 4_300_000
  end

  def test_entries_are_read_wherever_their_data_is
    zip = reader(ZipBuilder.build({"a.txt" => "a" * 100, "b.txt" => "b" * 100}, reverse: true))

    assert_equal(["b" * 100, "a" * 100], zip.entries.map { read_all(zip, it) })
  end

  def test_local_extra_fields_may_differ
    zip = reader(ZipBuilder.build([{name: "a.txt", data: "abc", local_extra: "\xCA\xFE\x02\x00ab".b}]))

    assert_equal "abc", read_all(zip, zip.entries.first)
  end

  def test_empty_entry
    zip = reader(ZipBuilder.build({"a.txt" => ""}))

    assert_raises(EOFError) { zip.member(zip.entries.first).readpartial(10) }
  end

  def test_a_wrong_crc
    assert_equal "a.zip:a.txt: broken zip archive (wrong CRC32)", data_error([{name: "a.txt", data: "a", crc: 1}])
  end

  def test_a_wrong_size
    [0, 8].each do |method|
      assert_equal "a.zip:a.txt: broken zip archive (100 bytes instead of 101)",
                   data_error([{name: "a.txt", data: "a" * 100, size: 101, method:}])
    end
  end

  def test_more_data_than_the_size_stops_before_it_comes_out
    zip = reader(ZipBuilder.build([{name: "a.txt", data: "a" * 100, size: 10}]))
    error = assert_raises(Metacrunch::InputError) { zip.member(zip.entries.first).readpartial(5) }

    assert_equal "a.zip:a.txt: broken zip archive (more data than its size)", error.message
  end

  def test_deflate_data_that_ends_early
    data = ("a" * 1000) + Random.new(3).bytes(1000)
    compressed = ZipBuilder.deflate(data).bytesize

    assert_equal "a.zip:a.txt: broken zip archive (deflate data ends early)",
                 data_error([{name: "a.txt", data:, compressed_size: compressed - 5}])
  end

  def test_data_after_the_deflate_data
    compressed = ZipBuilder.deflate("abc").bytesize

    assert_equal "a.zip:a.txt: broken zip archive (data after the deflate data)",
                 data_error([{name: "a.txt", data: "abc", compressed_size: compressed + 2}])
  end

  def test_broken_deflate_data
    archive = ZipBuilder.build([{name: "a.txt", data: Random.new(4).bytes(500), method: 0}])
    archive[archive.index("PK\x01\x02".b) + 10, 2] = [8].pack("v")

    assert data_error(archive).start_with?("a.zip:a.txt: broken zip archive (broken deflate data (")
  end

  def test_no_local_file_header
    archive = ZipBuilder.build({"a.txt" => "abc"})
    central = archive.index("PK\x01\x02".b)

    [1, central + 10, archive.bytesize].each do |offset|
      broken = archive.dup.tap { it[central + 42, 4] = [offset].pack("V") }

      assert_equal "a.zip:a.txt: broken zip archive (no local file header)", data_error(broken)
    end
  end

  def test_data_beyond_the_end_of_the_archive
    assert_equal "a.zip:a.txt: broken zip archive (data beyond the end of the archive)",
                 data_error([{name: "a.txt", data: "abc", compressed_size: 10_000}])
  end

  def test_drain_checks_the_rest
    zip = reader(ZipBuilder.build([{name: "a.txt", data: "a" * 1000, crc: 1}]))
    member = zip.member(zip.entries.first)
    member.readpartial(10)
    error = assert_raises(Metacrunch::InputError) { member.drain }

    assert_equal "a.zip:a.txt: broken zip archive (wrong CRC32)", error.message
  end

  # Input refuses them before; a gem that reads parts of an archive with
  # Zip directly gets the reason, not a wrong size.
  def test_members_that_cannot_be_read
    zip = reader(ZipBuilder.build([{name: "a.txt", data: "a" * 100, method: 12}, {name: "b.txt", data: "b", flags: 1}]))
    errors = zip.entries.map { |entry| assert_raises(Metacrunch::InputError) { zip.member(entry) }.message }

    assert_equal ["a.zip:a.txt: is compressed with bzip2, which metacrunch cannot read",
                  "a.zip:b.txt: is encrypted, which metacrunch cannot read"], errors
  end

  def test_drain_reads_the_rest
    zip = reader(ZipBuilder.build({"a.txt" => "a" * 1000}))
    member = zip.member(zip.entries.first)
    member.readpartial(10)

    assert_nil member.drain
    assert_raises(EOFError) { member.readpartial(10) }
  end

  def test_position_is_reported
    offsets = []
    data = Random.new(5).bytes(200_000)
    archive = ZipBuilder.build([{name: "a.bin", data:, method: 0}])
    zip = Zip.new(StringIO.new(archive), "a.zip", position: ->(offset) { offsets << offset })
    read_all(zip, zip.entries.first)

    assert_equal offsets.sort, offsets
    assert_equal 30 + "a.bin".bytesize + data.bytesize, offsets.last
  end

  private

  def reader(bytes) = Zip.new(StringIO.new(bytes), "a.zip")

  # The most bytes one call of the inflater gave while data was read.
  def largest_inflate(data)
    sizes = []
    recorder = Module.new do
      define_method(:inflate) { |*args, **opts| super(*args, **opts).tap { sizes << it.bytesize } }
    end
    Zlib::Inflate.prepend(recorder)
    zip = reader(ZipBuilder.build([{name: "data", data:}]))

    assert_equal data.bytesize, read_all(zip, zip.entries.first).bytesize
    sizes.max
  ensure
    recorder&.send(:remove_method, :inflate)
  end

  def read_all(zip, entry)
    member = zip.member(entry)
    data = +"".b
    loop { data << member.readpartial(65_536) }
  rescue EOFError
    data
  end

  # The error from reading the first entry; entries: an archive or the
  # entries to build one from.
  def data_error(entries)
    zip = reader(entries.is_a?(String) ? entries : ZipBuilder.build(entries))
    assert_raises(Metacrunch::InputError) { read_all(zip, zip.entries.first) }.message
  end

  # Entries of every kind: directories (by name, Unix mode, MS-DOS
  # attribute), a link, documents (FIFO, a mode without a type, MS-DOS),
  # dot entries and encrypted ones.
  def kinds
    reader(ZipBuilder.build(
             [{name: "d/", method: 0}, {name: "e", mode: 0o040755}, {name: "f", host: 0, mode: 0, dos: 0x10},
              {name: "l", mode: 0o120777}, {name: "fifo", mode: 0o010660}, {name: "plain", mode: 0o000644},
              {name: "__MACOSX/._a.txt"}, {name: "d/.DS_Store"}, {name: "x", flags: 1}, {name: "y", flags: 64},
              {name: "z", method: 99}, {name: "dos.txt", host: 0, mode: 0}]
           )).entries
  end

  def names(bytes) = reader(bytes).entries.map(&:name)

  def error(bytes) = assert_raises(Metacrunch::InputError) { reader(bytes) }.message

end
