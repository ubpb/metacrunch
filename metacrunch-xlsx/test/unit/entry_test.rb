# frozen_string_literal: true

require "test_helper"

class EntryTest < Minitest::Test

  include Helpers

  Entry = Metacrunch::Xlsx::Entry

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_an_entry_is_deflated_with_crc_and_sizes
    path = zip("a.xml" => ["<a>", "text", "</a>"])

    assert_equal({"a.xml" => "<a>text</a>"}, parts(path))
  end

  # A signal (Ctrl-C) that wakes the thread inside zlib makes Zlib::Deflate
  # raise Zlib::BufError, although it keeps the input it did not take.
  # Waking the thread all the time does the same.
  def test_wakeups_inside_zlib_do_not_break_the_entry
    pieces = Array.new(50_000) { %(<row r="#{it}"><c><v>#{it}</v></c></row>) }
    waker = Thread.new { loop { Thread.main.wakeup && Thread.pass } }
    path = zip("sheet.xml" => pieces)
    waker.kill.join
    entry = Zip::File.open(path) { it.find_entry("sheet.xml") }

    assert_equal pieces.join, parts(path).fetch("sheet.xml")
    assert_equal Zlib.crc32(pieces.join), entry.crc
  end

  private

  # A ZIP file with an Entry for each name, written in the given pieces.
  def zip(entries)
    path = File.join(@dir, "test.zip")
    File.open(path, "wb") do |file|
      streamer = ZipKit::Streamer.new(file)
      entries.each do |name, pieces|
        entry = Entry.new(streamer, name)
        pieces.each { entry << it }
        entry.close
      end
      streamer.close
    end
    path
  end

end
