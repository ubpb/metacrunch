# frozen_string_literal: true

require "test_helper"
require "digest"
require "metacrunch/testing"
require "tmpdir"

class FileListReaderTest < Minitest::Test

  Reader = Metacrunch::FileList::Reader

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.chmod_R("u+rwx", @dir)
    FileUtils.remove_entry(@dir)
  end

  def test_reads_a_directory_recursively_sorted_by_path
    touch("docs/b.txt")
    touch("docs/a/c.md")
    records = read(path("docs"))

    assert_equal(["a/c.md", "b.txt"], records.map { it["id"] })
    assert_equal ["id", "path", "size", "modified", "type", "sha256", "content"], records.first.keys
  end

  def test_the_fields_of_a_record
    touch("d/notes.MD", "\xFFbytes".b)
    file = read(path("d")).first

    assert_equal [File.expand_path(path("d/notes.MD")), 6, "text/markdown"], file.values_at("path", "size", "type")
    assert_equal File.mtime(path("d/notes.MD")).utc.iso8601, file["modified"]
    assert_equal [Digest::SHA256.hexdigest("\xFFbytes".b), "\xFFbytes".b, Encoding::BINARY],
                 [file["sha256"], file["content"], file["content"].encoding]
  end

  def test_a_pattern_has_its_fixed_start_as_root
    touch("site/a.html")
    touch("site/x/b.pdf")
    touch("site/c.txt")

    assert_equal ["a.html", "x/b.pdf"], ids(path("site/**/*.{html,pdf}"))
  end

  def test_a_pattern_without_a_directory_has_the_current_one_as_root
    touch("a.md")
    touch("b.txt")

    Dir.chdir(@dir) { assert_equal ["a.md"], ids("*.md") }
  end

  def test_several_targets_share_one_root
    touch("d/reports/a.md")
    touch("d/notes/a.md")
    touch("d/notes/b.txt")

    assert_equal ["notes/a.md", "reports/a.md"], ids([path("d/reports"), path("d/notes/*.md")])
  end

  def test_a_file_target_uses_its_directory
    touch("d/x/a.pdf")

    assert_equal ["a.pdf"], ids(path("d/x/a.pdf"))
  end

  def test_an_explicit_root
    touch("d/x/a.pdf")

    assert_equal ["x/a.pdf"], ids(path("d/x"), root: path("d"))
  end

  def test_a_file_outside_root_is_invalid
    touch("e/a.md")
    records = read(path("e/a.md"), root: path("d"))

    assert_equal [Metacrunch::InvalidRecord], records.map(&:class)
    assert_equal File.expand_path(path("e/a.md")), records.first.raw
    assert_equal "outside root #{File.expand_path(path("d"))}", records.first.error.message
  end

  def test_a_file_matched_twice_is_read_once
    touch("d/a.md")

    assert_equal ["a.md"], ids([path("d"), path("d/*.md"), path("d/a.md")])
  end

  def test_directories_matched_by_a_pattern_are_skipped
    touch("d/sub.md/inner.txt")
    touch("d/a.md")

    assert_equal ["a.md"], ids(path("d/*.md"))
  end

  def test_hidden_files_only_where_a_pattern_names_them
    touch("d/.secret")
    touch("d/a.md")

    assert_equal ["a.md"], ids(path("d"))
    assert_equal [".secret"], ids(path("d/.*"))
  end

  def test_symlinked_directories_are_not_followed
    touch("d/real/x.md")
    File.symlink(path("d/real"), path("d/link"))

    assert_equal ["real/x.md"], ids(path("d"))
  end

  def test_types_by_extension
    ["A.PDF", "x.docx", "README", "x.bin", "page.htm", "notes.markdown"].each { touch("d/#{it}") }
    types = read(path("d")).to_h { [it["id"], it["type"]] }

    assert_equal({"A.PDF" => "application/pdf", "README" => "application/octet-stream",
                  "notes.markdown" => "text/markdown", "page.htm" => "text/html",
                  "x.bin" => "application/octet-stream",
                  "x.docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document"}, types)
  end

  def test_the_type_table
    expected = {"html" => "text/html", "htm" => "text/html", "xhtml" => "application/xhtml+xml",
                "pdf" => "application/pdf", "doc" => "application/msword",
                "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "xls" => "application/vnd.ms-excel",
                "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "ppt" => "application/vnd.ms-powerpoint",
                "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                "odt" => "application/vnd.oasis.opendocument.text",
                "ods" => "application/vnd.oasis.opendocument.spreadsheet",
                "odp" => "application/vnd.oasis.opendocument.presentation", "rtf" => "application/rtf",
                "txt" => "text/plain", "md" => "text/markdown", "markdown" => "text/markdown",
                "xml" => "application/xml", "json" => "application/json", "csv" => "text/csv",
                "epub" => "application/epub+zip", "eml" => "message/rfc822"}

    assert_equal expected, Metacrunch::FileList::TYPES
    assert_equal "application/pdf", Metacrunch::FileList.type("a/b.Pdf")
  end

  def test_unicode_names
    touch("d/Öffnungszeiten 2026.md")

    assert_equal ["Öffnungszeiten 2026.md"], ids(path("d"))
  end

  def test_a_name_that_is_not_utf8_is_invalid
    begin
      touch("d/bad\xFF.txt".b)
    rescue SystemCallError
      skip "the file system refuses names that are not UTF-8"
    end

    assert_equal [Metacrunch::InvalidRecord], read(path("d")).map(&:class)
  end

  def test_an_unreadable_file_is_invalid
    skip "root reads every file" if Process.uid.zero?
    touch("d/a.md")
    touch("d/b.md")
    File.chmod(0o000, path("d/a.md"))
    records = read(path("d"))

    assert_equal [Metacrunch::InvalidRecord, Hash], records.map(&:class)
    assert_kind_of Errno::EACCES, records.first.error
  end

  def test_nothing_matched_yields_nothing
    assert_empty read(path("nothing/**/*.md"))
    assert_empty read(path("missing"))
  end

  def test_progress
    touch("d/a.md")
    touch("d/b.md")
    reader = Reader.new(path("d"))
    before = reader.progress
    seen = reader.each.map { reader.progress }

    assert_equal [0.0, [0.5, 1.0], 1.0], [before, seen, reader.progress]
  end

  def test_progress_when_nothing_matched
    reader = Reader.new(path("missing"))
    reader.each.to_a

    assert_in_delta 1.0, reader.progress
  end

  def test_wrong_arguments
    [[], 42, [nil], [path("d"), 1]].each do |targets|
      assert_raises(ArgumentError, targets.inspect) { Reader.new(targets) }
    end
    assert_raises(ArgumentError) { Reader.new(path("d"), root: 1) }
  end

  def test_pathnames
    touch("d/a.md")

    assert_equal ["a.md"], ids(Pathname(path("d")))
    assert_equal ["d/a.md"], ids([Pathname(path("d/*.md"))], root: Pathname(@dir))
  end

  def test_in_a_job
    touch("d/a.md", "# A")
    touch("d/b.md", "# B")
    reader = Reader.new(path("d"))
    job = Metacrunch.job { source reader, id: ->(file) { file["id"] } }
    result = Metacrunch::Testing.run(job)

    assert_equal(["# A", "# B"], result.records.map { it["content"] })
  end

  private

  def path(relative) = File.join(@dir, relative)

  def touch(relative, bytes = "x")
    FileUtils.mkdir_p(File.dirname(path(relative)))
    File.binwrite(path(relative), bytes)
  end

  def read(targets, **) = Reader.new(targets, **).each.to_a

  def ids(targets, **) = read(targets, **).map { it["id"] }

end
