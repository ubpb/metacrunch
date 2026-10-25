# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tmpdir"

class InputTarTest < Minitest::Test

  Input = Metacrunch::Input

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_every_regular_member_is_a_document
    path = write("records.tar", tar("data/a.jsonl" => "1\n", "data/b.jsonl" => "2\n"))

    assert_equal [["#{path}:data/a.jsonl", "1\n"], ["#{path}:data/b.jsonl", "2\n"]], documents(path)
  end

  def test_tar_gz_with_and_without_a_matching_name
    archive = Zlib.gzip(tar("a.jsonl" => "1\n"))

    ["records.tar.gz", "records.tgz", "records.dat"].each do |name|
      path = write(name, archive)

      assert_equal [["#{path}:a.jsonl", "1\n"]], documents(path)
    end
  end

  def test_members_are_detected_again
    inner = tar("c.jsonl" => "3\n")
    path = write("outer.tar", tar("a.jsonl.gz" => Zlib.gzip("1\n"), "inner.tar" => inner))

    assert_equal [["#{path}:a.jsonl.gz", "1\n"], ["#{path}:inner.tar:c.jsonl", "3\n"]], documents(path)
  end

  def test_directories_links_pax_headers_and_dot_members_are_skipped
    path = write("mixed.tar", tar("d/" => :directory, "link" => :symlink, "PaxHeader/a.jsonl" => :pax,
                                  "._a.jsonl" => "\x00\x05\x16\x07junk", "d/.DS_Store" => "junk",
                                  "a.jsonl" => "1\n"))

    assert_equal [["#{path}:a.jsonl", "1\n"]], documents(path)
  end

  # POSIX: "0", NUL (older tars) and "7" (contiguous file) are regular files.
  def test_all_kinds_of_regular_members_are_documents
    data = "1\n"
    members = ["0", "\0", "7"].map do |flag|
      header = Gem::Package::TarHeader.new(name: "flag-#{flag.ord}.jsonl", mode: 0o644, size: data.bytesize,
                                           typeflag: flag, prefix: "", mtime: 0)
      header.to_s + data.ljust(512, "\0")
    end
    path = write("flags.tar", members.join + ("\0" * 1024))
    names = documents(path).map { it.first.split(":").last }

    assert_equal ["flag-48.jsonl", "flag-0.jsonl", "flag-55.jsonl"], names
  end

  def test_members_read_only_in_part_do_not_disturb_the_next_one
    path = write("records.tar", tar("a.jsonl" => "a" * 3000, "b.jsonl" => "b" * 3000))
    heads = []
    Input.new(path).each_document { |stream, _name| heads << stream.read(2) }

    assert_equal ["aa", "bb"], heads
  end

  def test_an_archive_cut_inside_a_member_s_data
    path = write("cut.tar", tar("a.txt" => "a" * 3000).byteslice(0, 512 + 1000))
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}:a.txt: broken tar archive (ends inside the member's data)", error.message
  end

  def test_a_member_read_only_in_part_is_still_checked
    path = write("cut.tar", tar("a.txt" => "a" * 3000).byteslice(0, 512 + 1000))

    assert_raises(Metacrunch::InputError) { Input.new(path).each_document { |stream, _name| stream.read(10) } }
  end

  def test_an_archive_cut_inside_a_block
    archive = tar("a.txt" => "a" * 3000, "b.txt" => "b" * 3000)

    [512 + 3072 + 100, 512 + 3000 + 10].each do |cut|
      path = write("cut#{cut}.tar", archive.byteslice(0, cut))
      error = assert_raises(Metacrunch::InputError) { documents(path) }

      assert_equal "#{path}: broken tar archive (ends inside a 512-byte block)", error.message
    end
  end

  def test_a_missing_end_marker_is_accepted
    archive = tar("a.txt" => "a" * 3000)
    path = write("noend.tar", archive.byteslice(0, 512 + 3072))

    assert_equal [["#{path}:a.txt", "a" * 3000]], documents(path)
  end

  def test_a_broken_header
    archive = tar("a.txt" => "a")
    archive.setbyte(148, "9".ord)
    path = write("bad.tar", archive)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_match(/\A#{Regexp.escape(path)}: broken tar archive \(.*octal.*\)\z/, error.message)
  end

  # gzip checks its CRC and length at its end, behind the end of the tar
  # archive; stored blocks keep the flipped byte from breaking the deflate
  # data first.
  def test_a_tar_gz_with_a_wrong_checksum_raises
    archive = Zlib.gzip(tar("a.bin" => Random.new(3).bytes(100_000)), level: 0)
    archive.setbyte(archive.bytesize / 2, archive.getbyte(archive.bytesize / 2) ^ 1)
    path = write("corrupt.tgz", archive)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_match(/\A#{Regexp.escape(path)}: broken gzip data \(.*crc/, error.message)
  end

  def test_a_tar_gz_without_its_footer_raises
    archive = Zlib.gzip(tar("a.bin" => Random.new(3).bytes(100_000)))
    path = write("cut.tgz", archive.byteslice(0, archive.bytesize - 4))
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_match(/\A#{Regexp.escape(path)}: broken gzip data/, error.message)
  end

  # A changed name keeps an octal checksum field, but not the right sum.
  def test_a_wrong_header_checksum_raises
    archive = tar("a.txt" => "a")
    archive.setbyte(0, "b".ord)
    path = write("badsum.tar", archive)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}: broken tar archive (wrong header checksum)", error.message
  end

  def test_headers_with_the_signed_checksum_of_old_tars_are_read
    archive = tar("é.txt" => "a")
    bytes = archive.byteslice(0, 512).bytes
    bytes[148, 8] = Array.new(8, 32)
    archive[148, 8] = format("%06o\0 ", bytes.sum { it > 127 ? it - 256 : it })
    path = write("signed.tar", archive)

    assert_equal [["#{path}:é.txt", "a"]], documents(path)
  end

  def test_a_nul_in_a_member_name_raises
    data = "1\n"
    header = Gem::Package::TarHeader.new(name: "a\0b.jsonl", mode: 0o644, size: data.bytesize, prefix: "", mtime: 0)
    path = write("nul.tar", header.to_s + data.ljust(512, "\0") + ("\0" * 1024))
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}: broken tar archive (a member name contains a NUL byte)", error.message
  end

  def test_tar_counts_as_a_layer
    data = tar("a" => Zlib.gzip(Zlib.gzip(Zlib.gzip(Zlib.gzip("x")))))
    path = write("deep.tar", data)
    error = assert_raises(Metacrunch::InputError) { documents(path) }

    assert_equal "#{path}:a: more than 4 layers of gzip and tar", error.message
  end

  def test_breaking_out_of_a_nested_member_closes_the_file_quietly
    path = write("records.tgz", Zlib.gzip(tar("a.jsonl.gz" => Zlib.gzip("1\n" * 100_000), "b.jsonl" => "2\n")))
    _, stderr = capture_io do
      verbose = $VERBOSE
      $VERBOSE = true
      Input.new(path).each_document { |stream, _name| break stream.each_line.first }
    ensure
      $VERBOSE = verbose
    end

    assert_empty stderr
    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  def test_macos_tar_archives
    skip "needs /usr/bin/tar (bsdtar)" unless File.executable?("/usr/bin/tar") && RUBY_PLATFORM.include?("darwin")
    source = File.join(@dir, "src")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "a.jsonl"), "1\n")
    path = File.join(@dir, "mac.tgz")
    system("/usr/bin/tar", "-czf", path, "-C", source, "a.jsonl", exception: true)

    assert_equal [["#{path}:a.jsonl", "1\n"]], documents(path)
  end

  def test_progress_of_a_tar_gz
    input = Input.new(write("records.tgz", Zlib.gzip(tar("a.jsonl" => "1\n"))))
    input.each_document { |stream, _name| stream.read }

    assert_in_delta 1.0, input.progress
  end

  private

  def documents(target)
    result = []
    Input.new(target).each_document { |stream, name| result << [name, stream.read] }
    result
  end

  # entries: name => content, or :directory, :symlink, :pax.
  def tar(entries)
    io = StringIO.new(+"", "wb")
    Gem::Package::TarWriter.new(io) do |writer|
      entries.each do |name, content|
        case content
        when :directory then writer.mkdir(name, 0o755)
        when :symlink then writer.add_symlink(name, "a.jsonl", 0o777)
        when :pax then pax(io, name)
        else writer.add_file_simple(name, 0o644, content.bytesize) { it.write(content) }
        end
      end
    end
    io.string
  end

  # A pax header entry (typeflag "x"), as bsdtar writes them.
  def pax(io, name)
    data = "30 path=a-name-longer-than-ustar\n"
    header = Gem::Package::TarHeader.new(name:, mode: 0o644, size: data.bytesize, typeflag: "x", prefix: "",
                                         mtime: 0)
    io.write(header.to_s)
    io.write(data.ljust(512, "\0"))
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

end
