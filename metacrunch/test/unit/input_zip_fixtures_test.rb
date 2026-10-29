# frozen_string_literal: true

require "test_helper"
require "digest"

# The archives in test/fixtures/zip come from Go's test data (see its
# README); the expected digests were taken with Python's zipfile.
class InputZipFixturesTest < Minitest::Test

  Zip = Metacrunch::Input::Zip
  DIR = File.expand_path("../fixtures/zip", __dir__)
  EMPTY = Digest::SHA256.hexdigest("")
  HELLO = {"hello" => "6536d4feae10cf69a35efe7b0e4abedbc7c8c7bac12d89232b7dfcf5f387927c",
           "dir/bar" => "39dd73e4dae46b506e7f9b41066f7f21e5d61dadd4d2b5806d31e364886c2d08",
           "readonly" => "779ea758cdca523be3302725bd89ced1d0c3499db16fa80580bcf731a7de2099"}.freeze
  FOO_BAR = {"foo.txt" => "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c",
             "bar.txt" => "7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730"}.freeze
  README = {"README" => "4fe486822766313001f00f7a4ce2176271e19a65f0a915d98c8777fdbb9eb142"}.freeze

  ARCHIVES = {
    "crc32-not-streamed.zip" => FOO_BAR,
    "dd.zip" => {"filename" => "7d33d9ba6defc9dca6e8c24e3d1d286650a5d11912f0abf1475c76af28cf77ce"},
    "go-no-datadesc-sig.zip" => FOO_BAR,
    "symlink.zip" => {},
    "test-trailing-junk.zip" => {
      "test.txt" => "3162f80e9db2a1c7229ce55d6dbc8c4496936f66c7df5136d24e8f9973cf64bc",
      "gophercolor16x16.png" => "f29bb9177d08fb50027e74a37eb00a69906a5994dc55a041670703efe4ecfdc9"
    },
    "unix.zip" => HELLO,
    "utf8-7zip.zip" => {"世界" => EMPTY},
    "utf8-infozip.zip" => {"世界" => EMPTY},
    "utf8-osx.zip" => {"世界" => EMPTY},
    "utf8-winrar.zip" => {"世界" => EMPTY},
    "utf8-winzip.zip" => {"世界" => EMPTY},
    "winxp.zip" => HELLO,
    "zip64-2.zip" => README,
    "zip64.zip" => README
  }.freeze

  def test_archives_of_other_writers
    ARCHIVES.each do |file, expected|
      assert_equal expected, documents(file), file
    end
  end

  def test_a_symlink_is_no_document
    links = open_zip("symlink.zip") { |zip| zip.entries.map(&:link?) }

    assert_equal [true], links
  end

  # Python reads it, Go refuses it too.
  def test_a_truncated_comment_is_refused
    error = assert_raises(Metacrunch::InputError) { open_zip("comment-truncated.zip") { nil } }

    assert_equal "comment-truncated.zip: broken zip archive (no end of central directory record)", error.message
  end

  private

  def open_zip(file)
    File.open(File.join(DIR, file), "rb") { |io| yield Zip.new(io, file) }
  end

  # Entry name => SHA-256 of its data, for the document entries.
  def documents(file)
    open_zip(file) do |zip|
      zip.entries.select(&:document?).to_h do |entry|
        member = zip.member(entry)
        digest = Digest::SHA256.new
        begin
          loop { digest << member.readpartial(65_536) }
        rescue EOFError
          nil
        end
        [entry.name, digest.hexdigest]
      end
    end
  end

end
