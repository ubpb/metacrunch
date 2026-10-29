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

  def test_maxed_values_without_zip64
    assert_equal "a.zip: broken zip archive (the Zip64 end record is missing)",
                 error(ZipBuilder.build({"a.txt" => "a"}, count: 0xFFFF))

    archive = ZipBuilder.build([{name: "a.txt", data: "a", size: 0xFFFF_FFFF}])

    assert_equal "a.zip: broken zip archive (an entry lacks its Zip64 extra field)", error(archive)
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

  private

  def reader(bytes) = Zip.new(StringIO.new(bytes), "a.zip")

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
