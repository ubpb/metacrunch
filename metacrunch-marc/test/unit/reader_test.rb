# frozen_string_literal: true

require "test_helper"
require "json"
require "rubygems/package"

class ReaderTest < Minitest::Test

  include Fixtures
  include Inputs
  include Iso

  Marc = Metacrunch::Marc
  Reader = Metacrunch::Marc::Reader
  IDS = ["book-1", "article-1", "holding-1"].freeze
  NOT_MARC = "is neither MARCXML, ISO 2709 nor MARC-in-JSON"

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_reads_records_from_a_path
    assert_equal IDS, ids(read(Reader.new(fixture_path("collection.xml"))))
  end

  def test_reads_pathnames_and_several_targets
    reader = Reader.new([Pathname(fixture_path("collection.xml")), fixture_path("local.xml")])

    assert_equal [*IDS, "local-1"], ids(read(reader))
  end

  def test_reads_stdin
    stdin = $stdin
    File.open(fixture_path("collection.xml")) do |file|
      $stdin = file

      assert_equal IDS, ids(read(Reader.new("-")))
    end
  ensure
    $stdin = stdin
  end

  def test_reads_an_io_and_leaves_it_open
    File.open(fixture_path("collection.xml")) do |file|
      assert_equal IDS, ids(read(Reader.new(file)))
      refute_predicate file, :closed?
    end
  end

  def test_reads_gzip_files
    path = write("records.xml.gz", Zlib.gzip(fixture("collection.xml")))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_reads_all_members_of_a_gzip_file
    path = write("cat.xml.gz", Zlib.gzip(fixture("collection.xml")) + Zlib.gzip(fixture("local.xml")))

    assert_equal [*IDS, "local-1"], ids(read(Reader.new(path)))
  end

  def test_garbage_after_gzip_data_raises
    path = write("garbage.xml.gz", "#{Zlib.gzip(fixture("collection.xml"))}garbage")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal "#{path}: data after the end of the gzip data", error.message
  end

  def test_reads_gzip_whatever_the_name
    path = write("records.xml", Zlib.gzip(fixture("collection.xml")))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_xml_after_a_byte_order_mark_and_whitespace
    path = write("bom.xml", "\xEF\xBB\xBF\n  #{fixture("local.xml")}".b)

    assert_equal ["local-1"], ids(read(Reader.new(path)))
  end

  def test_a_broken_tar_gz_raises
    path = write("broken.tar.gz", Zlib.gzip(tar("a.xml" => fixture("collection.xml"))).byteslice(0, 40))

    assert_match(/broken gzip data/, assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }.message)
  end

  def test_stopping_inside_a_gzip_file
    path = write("records.xml.gz", Zlib.gzip(fixture("collection.xml")))
    first = Reader.new(path).each { break it }

    assert_equal "book-1", first["001"].value
  end

  def test_reads_tar_archives
    archive = tar("a.xml" => fixture("collection.xml"), "b.xml" => fixture("local.xml"))
    paths = [write("records.tar", archive), write("records.tar.gz", Zlib.gzip(archive)),
             write("records.tgz", Zlib.gzip(archive))]

    paths.each { assert_equal [*IDS, "local-1"], ids(read(Reader.new(it))) }
  end

  def test_parse_false_yields_record_strings
    items = read(Reader.new(fixture_path("collection.xml"), parse: false))

    assert(items.all? { it.is_a?(String) && it.start_with?("<record") })
    assert_equal(Marc::Xml.each(fixture("collection.xml")).to_a, items.map { Marc::Xml.parse(it) })
  end

  def test_a_broken_record_is_an_invalid_record
    xml = ["<collection>", %(<record><controlfield tag="001">1</controlfield></record>),
           %(<record><controlfield tag="001">2</record>),
           %(<record><controlfield tag="001">3</controlfield></record>), "</collection>"].join
    items = read(Reader.new(write("broken.xml", xml)))

    assert_equal [Marc::Record, Metacrunch::InvalidRecord, Marc::Record], items.map(&:class)
    assert_equal %(<record><controlfield tag="001">2</record>), items[1].raw
    assert_instance_of Marc::ParseError, items[1].error
  end

  def test_a_truncated_file_ends_with_an_invalid_record
    xml = fixture("collection.xml")
    items = read(Reader.new(write("cut.xml", xml[0, xml.index("holding-1")])))

    assert_equal [Marc::Record, Marc::Record, Metacrunch::InvalidRecord], items.map(&:class)
  end

  def test_a_control_character_makes_an_invalid_record
    xml = ["<collection>", %(<record><controlfield tag="001">1</controlfield></record>),
           "<record><controlfield tag=\"001\">2\x1F</controlfield></record>",
           %(<record><controlfield tag="001">3</controlfield></record>), "</collection>"].join
    items = read(Reader.new(write("control.xml", xml)))

    assert_equal [Marc::Record, Metacrunch::InvalidRecord, Marc::Record], items.map(&:class)
  end

  def test_values_that_are_not_utf8_make_an_invalid_record
    xml = "<collection><record><controlfield tag=\"001\">M\xFCller</controlfield></record></collection>".b

    assert_instance_of Metacrunch::InvalidRecord, read(Reader.new(write("latin1.xml", xml))).first
  end

  def test_concatenated_files_and_bare_records
    assert_equal 6, read(Reader.new(write("cat.xml", fixture("collection.xml") * 2))).size
    assert_equal 2, read(Reader.new(write("bare.xml", "<record/><record/>"))).size
  end

  def test_normalize
    path = write("nfd.xml", %(<record><controlfield tag="001">Mu\u0308ller</controlfield></record>))

    assert_equal "Müller", read(Reader.new(path, normalize: :nfc)).first["001"].value
  end

  def test_each_without_a_block_is_an_enumerator
    assert_equal ["book-1", "article-1"], ids(Reader.new(fixture_path("collection.xml")).each.first(2))
  end

  def test_rejects_invalid_arguments
    assert_raises(ArgumentError) { Reader.new([]) }
    assert_raises(ArgumentError) { Reader.new(42) }
    assert_raises(ArgumentError) { Reader.new("a.xml", normalize: :nfd) }
  end

  def test_progress
    records = Array.new(3000) { %(<record><controlfield tag="001">#{it}</controlfield></record>) }
    reader = Reader.new(write("many.xml", "<collection>#{records.join("\n")}</collection>"))
    progress = reader.enum_for(:each).map { reader.progress }

    assert_equal progress.sort, progress
    assert(progress.any? { it.positive? && it < 1.0 })
    assert_in_delta 1.0, reader.progress
  end

  def test_no_progress_before_reading_and_for_ios
    File.open(fixture_path("collection.xml")) do |file|
      reader = Reader.new(file)
      read(reader)

      assert_nil Reader.new(fixture_path("collection.xml")).progress
      assert_nil reader.progress
    end
  end

  def test_progress_of_an_empty_file
    reader = Reader.new(write("empty.xml", ""))

    assert_empty read(reader)
    assert_in_delta 1.0, reader.progress
  end

  def test_reads_a_named_pipe_without_progress
    path = File.join(@dir, "fifo")
    File.mkfifo(path)
    writer = Thread.new { File.write(path, fixture("collection.xml")) }
    reader = Reader.new(path)

    assert_equal IDS, ids(read(reader))
    assert_nil reader.progress
  ensure
    writer&.join
  end

  def test_closes_files_on_break_and_on_errors
    path = fixture_path("collection.xml")
    Reader.new(path).each { break }

    assert_raises(RuntimeError) { Reader.new(path).each { raise "stop" } }
    assert_empty(ObjectSpace.each_object(File).select { !it.closed? && it.path == path })
  end

  def test_a_missing_file_raises
    missing = File.join(@dir, "missing.xml")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(missing)) }

    assert_equal "#{missing}: no such file", error.message
  end

  def test_broken_gzip_raises
    broken = write("broken.gz", Zlib.gzip(fixture("collection.xml")).byteslice(0, 30))

    assert_match(/broken gzip data/, assert_raises(Metacrunch::InputError) { read(Reader.new(broken)) }.message)
  end

  def test_reads_tar_archives_whatever_the_name
    path = write("records.dat", tar("a.xml.gz" => Zlib.gzip(fixture("collection.xml"))))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_skips_members_whose_names_start_with_a_dot
    hidden = %(<record><controlfield tag="001">hidden-1</controlfield></record>)
    archive = tar("._a.xml" => hidden, "a.xml" => fixture("collection.xml"))

    assert_equal IDS, ids(read(Reader.new(write("mac.tar", archive))))
  end

  def test_a_truncated_tar_raises
    archive = tar("a.xml" => fixture("collection.xml"))
    path = write("cut.tar", archive.byteslice(0, 2048))
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_match(/broken tar archive \(ends inside the member's data\)/, error.message)
  end

  def test_a_file_that_is_not_marc_raises
    path = write("data.csv", "id;title\n1;x\n")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal %(#{path}: #{NOT_MARC}: it starts with "id;title\\n1;x\\n"), error.message
  end

  def test_a_file_named_gz_that_is_not_gzip_is_detected
    path = write("plain.gz", "not gzip")

    assert_includes assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }.message, NOT_MARC
  end

  def test_detects_on_stdin_too
    stdin = $stdin
    $stdin = StringIO.new("id;title\n")
    error = assert_raises(Metacrunch::InputError) { read(Reader.new("-")) }

    assert_equal %(-: #{NOT_MARC}: it starts with "id;title\\n"), error.message
  ensure
    $stdin = stdin
  end

  def test_normalize_needs_parse
    error = assert_raises(ArgumentError) { Reader.new("a.xml", parse: false, normalize: :nfc) }

    assert_match(/Metacrunch::Marc\.parse\(raw, normalize: :nfc\)/, error.message)
  end

  def test_reads_iso2709_and_marc_in_json
    assert_equal IDS, ids(read(Reader.new(fixture_path("collection.mrc"))))
    assert_equal IDS, ids(read(Reader.new(fixture_path("collection.jsonl"))))
  end

  def test_reads_targets_in_different_formats
    targets = [fixture_path("collection.mrc"), fixture_path("local.xml"), fixture_path("collection.jsonl")]

    assert_equal [*IDS, "local-1", *IDS], ids(read(Reader.new(targets)))
  end

  def test_reads_iso2709_on_stdin
    stdin = $stdin
    File.open(fixture_path("collection.mrc")) do |file|
      $stdin = file

      assert_equal IDS, ids(read(Reader.new("-")))
    end
  ensure
    $stdin = stdin
  end

  def test_reads_a_slow_pipe_in_every_format
    ["collection.xml", "collection.mrc", "collection.jsonl"].each do |name|
      assert_equal IDS, ids(read(Reader.new(Trickle.new(File.binread(fixture_path(name)))))), name
    end
  end

  def test_reads_gzip_iso2709_files
    path = write("records.mrc.gz", Zlib.gzip(File.binread(fixture_path("collection.mrc"))))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_reads_a_tar_archive_with_all_three_formats
    archive = tar("a.xml" => fixture("collection.xml"), "b.mrc" => File.binread(fixture_path("collection.mrc")),
                  "c.jsonl" => fixture("collection.jsonl"))

    assert_equal IDS * 3, ids(read(Reader.new(write("all.tar", archive))))
  end

  def test_a_json_array_raises
    path = write("records.json", %([{"fields": []}]))
    error = assert_raises(Metacrunch::InputError) { read(Reader.new(path)) }

    assert_equal "#{path}: is a JSON array of records; convert it to one record per line first, e.g. " \
                 "jq -c '.[]' in.json > out.jsonl", error.message
  end

  def test_json_that_is_not_marc_is_an_invalid_record
    item = read(Reader.new(write("data.jsonl", %({"id": 1}\n)))).first

    assert_instance_of Metacrunch::InvalidRecord, item
    assert_equal %(unknown key "id"; a record has "leader" and "fields"), item.error.message
  end

  def test_iso2709_after_a_byte_order_mark
    path = write("bom.mrc", "\xEF\xBB\xBF".b + File.binread(fixture_path("collection.mrc")))

    assert_equal IDS, ids(read(Reader.new(path)))
  end

  def test_parse_false_yields_iso2709_and_json_strings
    expected = Marc::Xml.each(fixture("collection.xml")).map(&:fields)

    ["collection.mrc", "collection.jsonl"].each do |name|
      items = read(Reader.new(fixture_path(name), parse: false))

      assert_equal(expected, items.map { Marc.parse(it).fields }, name)
    end
  end

  def test_parse_false_with_marc_parse_reads_what_parse_true_reads
    broken = book("2")
    broken[12, 5] = "     "
    path = write("leaders.mrc", book("1") + broken)

    assert_equal ids(read(Reader.new(path))), ids(read(Reader.new(path, parse: false)).map { Marc.parse(it) })
  end

  def test_a_broken_iso2709_record_is_an_invalid_record
    broken = book("2").sub("Title", "Ti\x1Etle")
    items = read(Reader.new(write("broken.mrc", book("1") + broken + book("3"))))

    assert_equal [Marc::Record, Metacrunch::InvalidRecord, Marc::Record], items.map(&:class)
    assert_equal broken, items[1].raw.b
    assert_equal "the directory has 2 entries, the data 3 fields", items[1].error.message
  end

  def test_bytes_after_the_last_iso2709_record
    items = read(Reader.new(write("eof.mrc", "#{File.binread(fixture_path("collection.mrc"))}\x1A".b)))

    assert_equal [Marc::Record, Marc::Record, Marc::Record, Metacrunch::InvalidRecord], items.map(&:class)
    assert_equal "the input ended inside a record", items.last.error.message
  end

  def test_a_broken_json_line_is_an_invalid_record
    lines = [%({"fields": [{"001": "1"}]}), %({"fields": [{"001": 2}]}), %({"fields": [{"001": "3"}]})]
    items = read(Reader.new(write("broken.jsonl", lines.join("\n"))))

    assert_equal [Marc::Record, Metacrunch::InvalidRecord, Marc::Record], items.map(&:class)
    assert_equal lines[1], items[1].raw
  end

  def test_a_pretty_printed_json_file
    items = read(Reader.new(write("pretty.json", JSON.pretty_generate({"fields" => [{"001" => "1"}]}))))

    assert(items.all?(Metacrunch::InvalidRecord))
    assert_includes items.first.error.message, "MARC-in-JSON has one record per line"
  end

  def test_normalize_iso2709_and_json
    nfd = Marc::Record.new(fields: [Marc::ControlField.new("001", "Mu\u0308ller")])

    [write("nfd.mrc", nfd.to_iso2709), write("nfd.jsonl", nfd.to_json)].each do |path|
      assert_equal "Müller", read(Reader.new(path, normalize: :nfc)).first["001"].value
    end
  end

  private

  def read(reader) = reader.enum_for(:each).to_a

  def ids(records) = records.map { it["001"].value }

  def write(name, content)
    path = File.join(@dir, name)
    File.binwrite(path, content)
    path
  end

  def tar(entries)
    io = StringIO.new
    Gem::Package::TarWriter.new(io) do |tar|
      tar.mkdir("data", 0o755)
      entries.each do |name, content|
        tar.add_file_simple("data/#{name}", 0o644, content.bytesize) { it.write(content) }
      end
    end
    io.string
  end

end
