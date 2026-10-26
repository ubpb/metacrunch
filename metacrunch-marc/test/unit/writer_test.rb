# frozen_string_literal: true

require "test_helper"
require "json"

class WriterTest < Minitest::Test

  include Fixtures

  Marc = Metacrunch::Marc
  Writer = Metacrunch::Marc::Writer
  HEADER = %(<?xml version="1.0" encoding="UTF-8"?>\n<collection xmlns="http://www.loc.gov/MARC21/slim">\n)

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  # A pipe that breaks when the buffered data is flushed at the end.
  class PipeClosedBeforeFlush < StringIO

    def flush = raise(Errno::EPIPE)

  end

  def setup
    @dir = Dir.mktmpdir
    @ctx = Metacrunch::Context.new(id: "1", position: 3, logger: Logger.new(nil))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_writes_a_collection
    io = StringIO.new
    writer = open_writer(io)
    writer.write(record, @ctx)
    writer.close
    expected = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <collection xmlns="http://www.loc.gov/MARC21/slim">
        <record>
          <controlfield tag="001">1</controlfield>
        </record>
      </collection>
    XML

    assert_equal expected, io.string
  end

  def test_write_batch
    io = StringIO.new
    writer = open_writer(io)
    writer.write_batch([record, record], [@ctx, @ctx])
    writer.close

    assert_equal 2, Marc::Xml.each(io.string).count
  end

  def test_an_empty_run_gives_an_empty_collection
    io = StringIO.new
    open_writer(io).close

    assert_equal "#{HEADER}</collection>\n", io.string
  end

  def test_writes_empty_records
    io = StringIO.new
    writer = open_writer(io)
    writer.write(Marc::Record.new, @ctx)
    writer.close

    assert_equal [Marc::Record.new], Marc::Xml.each(io.string).to_a
  end

  def test_keeps_values_with_line_breaks
    records = Marc::Xml.each(fixture("edge.xml")).to_a
    io = StringIO.new
    writer = open_writer(io)
    records.each { writer.write(it, @ctx) }
    writer.close

    assert_equal records, Marc::Xml.each(io.string).to_a
  end

  def test_writes_files_and_gzip_files
    records = Marc::Xml.each(fixture("collection.xml")).to_a
    ["out.xml", "out.xml.gz"].each do |name|
      path = File.join(@dir, name)
      writer = open_writer(path)
      records.each { writer.write(it, @ctx) }
      writer.close
      content = name.end_with?(".gz") ? Zlib.gunzip(File.binread(path)) : File.read(path)

      assert_equal records, Marc::Xml.each(content).to_a
    end
  end

  def test_writes_to_a_pathname_and_closes_once
    path = Pathname(File.join(@dir, "out.xml"))
    writer = open_writer(path)
    writer.close
    writer.close

    assert_equal "#{HEADER}</collection>\n", File.read(path)
  end

  def test_writes_stdout_and_leaves_ios_open
    stdout = $stdout
    io = StringIO.new
    $stdout = io
    open_writer("-").close

    refute_predicate io, :closed?
    assert_equal "#{HEADER}</collection>\n", io.string
  ensure
    $stdout = stdout
  end

  def test_writes_record_xml_strings_as_they_are
    record = Marc::Xml.each(fixture("edge.xml")).first
    io = StringIO.new
    writer = open_writer(io)
    writer.write(record.to_xml(namespace: false), @ctx)
    writer.write_batch([%(<record><controlfield tag="001">2</controlfield></record>)], [@ctx])
    writer.close

    assert_equal [record, Marc::Xml.parse(%(<record><controlfield tag="001">2</controlfield></record>))],
                 Marc::Xml.each(io.string).to_a
  end

  def test_rejects_strings_that_are_not_records
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write("hello", @ctx) }

    assert_equal "record at position 3 is a String but not a <record> element", error.message
  end

  def test_rejects_records_of_other_classes
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write({"001" => "1"}, @ctx) }

    assert_equal "record at position 3 is not a Metacrunch::Marc::Record (Hash)", error.message
  end

  def test_records_that_cannot_be_written
    writer = open_writer(StringIO.new)
    bad = Marc::Record.new(fields: [Marc::ControlField.new("001", "\u0001")])
    error = assert_raises(Metacrunch::Error) { writer.write(bad, @ctx) }

    assert_match(/\Arecord at position 3 cannot be written as MARCXML: field 001: /, error.message)
  end

  def test_a_closed_pipe_raises_sigpipe_once
    writer = Writer.new(ClosedPipe.new, format: :xml)
    error = assert_raises(SignalException) { writer.open(nil) }
    writer.write(record, @ctx)
    writer.close

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_a_pipe_closed_before_the_final_flush_raises_sigpipe
    writer = open_writer(PipeClosedBeforeFlush.new)
    writer.write(record, @ctx)

    assert_raises(SignalException) { writer.close }
  end

  def test_close_after_a_failed_open_writes_nothing
    path = File.join(@dir, "missing", "out.xml")
    writer = Writer.new(path, format: :xml)

    assert_raises(Metacrunch::OutputError) { writer.open(nil) }
    assert_nil writer.close
    refute_path_exists path
  end

  def test_rejects_invalid_targets
    assert_raises(ArgumentError) { Writer.new(42, format: :xml) }
  end

  def test_refuses_names_it_cannot_write
    error = assert_raises(Metacrunch::OutputError) { open_writer(File.join(@dir, "out.xml.zst")) }

    assert_match(/cannot write zstd/, error.message)
  end

  def test_writes_iso2709_records_back_to_back
    io = StringIO.new
    writer = open_writer(io, format: :iso2709)
    writer.write(record, @ctx)
    writer.write_batch([record, record], [@ctx, @ctx])
    writer.close

    assert_equal record.to_iso2709 * 3, io.string
  end

  def test_writes_marc_in_json_lines
    io = StringIO.new
    writer = open_writer(io, format: :json)
    writer.write_batch([record, record], [@ctx, @ctx])
    writer.close

    assert_equal %({"fields":[{"001":"1"}]}\n) * 2, io.string
  end

  def test_an_empty_run_writes_nothing_in_iso2709_and_json
    [:iso2709, :json].each do |format|
      io = StringIO.new
      open_writer(io, format:).close

      assert_empty io.string, format
    end
  end

  def test_writes_gzip_files_in_every_format
    records = Marc::Xml.each(fixture("collection.xml")).to_a

    [:xml, :iso2709, :json].each do |format|
      path = File.join(@dir, "out.#{format}.gz")
      writer = open_writer(path, format:)
      records.each { writer.write(it, @ctx) }
      writer.close
      written = Marc::Formats.library(format).each(Zlib.gunzip(File.binread(path))).map(&:fields)

      assert_equal records.map(&:fields), written, format
    end
  end

  def test_writes_strings_of_its_format_as_they_are
    {iso2709: record.to_iso2709, json: JSON.generate(record.to_h)}.each do |format, string|
      io = StringIO.new
      writer = open_writer(io, format:)
      writer.write(string, @ctx)
      writer.close

      assert_equal [record.fields], Marc::Formats.library(format).each(io.string).map(&:fields), format
    end
  end

  def test_refuses_strings_of_another_format
    {xml: [record.to_iso2709, "a <record> element"], iso2709: [record.to_xml, "an ISO 2709 record"],
     json: [record.to_xml, "one line of MARC-in-JSON"]}.each do |format, (string, what)|
      error = assert_raises(Metacrunch::Error) { open_writer(StringIO.new, format:).write(string, @ctx) }

      assert_equal "record at position 3 is a String but not #{what}", error.message
    end
  end

  def test_refuses_json_strings_with_line_breaks
    error = assert_raises(Metacrunch::Error) { open_writer(StringIO.new, format: :json).write("{\n}", @ctx) }

    assert_equal "record at position 3 is a String but not one line of MARC-in-JSON", error.message
  end

  def test_checks_strings_with_invalid_utf8_without_raising_argument_error
    string = "x\xFF".dup.force_encoding(Encoding::UTF_8)
    error = assert_raises(Metacrunch::Error) { open_writer(StringIO.new).write(string, @ctx) }

    assert_equal "record at position 3 is a String but not a <record> element", error.message
  end

  def test_records_that_cannot_be_written_as_iso2709
    local = Marc::Xml.parse(fixture("local.xml"))
    error = assert_raises(Metacrunch::Error) { open_writer(StringIO.new, format: :iso2709).write(local, @ctx) }

    assert_equal "record at position 3 cannot be written as ISO 2709: field 852H: an ISO 2709 tag has 3 ASCII " \
                 "characters", error.message
  end

  def test_records_that_cannot_be_written_as_marc_in_json
    bad = Marc::Record.new(fields: [Marc::ControlField.new("001", "\u0001")])
    error = assert_raises(Metacrunch::Error) { open_writer(StringIO.new, format: :json).write(bad, @ctx) }

    assert_match(/\Arecord at position 3 cannot be written as MARC-in-JSON: field 001: /, error.message)
  end

  def test_oversize_records_stop_the_run_by_default
    error = assert_raises(Metacrunch::Error) { open_writer(StringIO.new, format: :iso2709).write(long, @ctx) }

    assert_match(/cannot be written as ISO 2709: field 500 has 10005 bytes/, error.message)
  end

  def test_oversize_allow
    io = StringIO.new
    writer = open_writer(io, format: :iso2709, oversize: :allow)
    writer.write(long, @ctx)
    writer.close

    assert_equal long.fields, Marc::Iso2709.parse(io.string).fields
  end

  def test_rejects_other_formats
    error = assert_raises(ArgumentError) { Writer.new(StringIO.new, format: :marc) }

    assert_equal "format must be :xml, :iso2709 or :json, got :marc", error.message
  end

  def test_rejects_other_oversize_values
    error = assert_raises(ArgumentError) { Writer.new(StringIO.new, format: :iso2709, oversize: :yes) }

    assert_equal "oversize must be :error or :allow, got :yes", error.message
  end

  def test_oversize_is_for_iso2709_only
    error = assert_raises(ArgumentError) { Writer.new(StringIO.new, format: :xml, oversize: :allow) }

    assert_equal "oversize: is for format: :iso2709 only", error.message
  end

  private

  def long = Marc::Record.new(fields: [Marc::DataField.new("500", " ", " ", [["a", "x" * 10_000]])])

  def record = Marc::Record.new(fields: [Marc::ControlField.new("001", "1")])

  def open_writer(target, format: :xml, **)
    writer = Writer.new(target, format:, **)
    writer.open(nil)
    writer
  end

end
