# frozen_string_literal: true

require "test_helper"

class WriterTest < Minitest::Test

  include Fixtures

  Marcxml = Metacrunch::Marcxml
  Writer = Metacrunch::Marcxml::Writer
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

    assert_equal 2, Marcxml.each(io.string).count
  end

  def test_an_empty_run_gives_an_empty_collection
    io = StringIO.new
    open_writer(io).close

    assert_equal "#{HEADER}</collection>\n", io.string
  end

  def test_writes_empty_records
    io = StringIO.new
    writer = open_writer(io)
    writer.write(Marcxml::Record.new, @ctx)
    writer.close

    assert_equal [Marcxml::Record.new], Marcxml.each(io.string).to_a
  end

  def test_keeps_values_with_line_breaks
    records = Marcxml.each(fixture("edge.xml")).to_a
    io = StringIO.new
    writer = open_writer(io)
    records.each { writer.write(it, @ctx) }
    writer.close

    assert_equal records, Marcxml.each(io.string).to_a
  end

  def test_writes_files_and_gzip_files
    records = Marcxml.each(fixture("collection.xml")).to_a
    ["out.xml", "out.xml.gz"].each do |name|
      path = File.join(@dir, name)
      writer = open_writer(path)
      records.each { writer.write(it, @ctx) }
      writer.close
      content = name.end_with?(".gz") ? Zlib.gunzip(File.binread(path)) : File.read(path)

      assert_equal records, Marcxml.each(content).to_a
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
    record = Marcxml.each(fixture("edge.xml")).first
    io = StringIO.new
    writer = open_writer(io)
    writer.write(record.to_xml(namespace: false), @ctx)
    writer.write_batch([%(<record><controlfield tag="001">2</controlfield></record>)], [@ctx])
    writer.close

    assert_equal [record, Marcxml.parse(%(<record><controlfield tag="001">2</controlfield></record>))],
                 Marcxml.each(io.string).to_a
  end

  def test_rejects_strings_that_are_not_records
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write("hello", @ctx) }

    assert_equal "record at position 3 is a String but not a <record> element", error.message
  end

  def test_rejects_records_of_other_classes
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write({"001" => "1"}, @ctx) }

    assert_equal "record at position 3 is not a Metacrunch::Marcxml::Record (Hash)", error.message
  end

  def test_records_that_cannot_be_written
    writer = open_writer(StringIO.new)
    bad = Marcxml::Record.new(fields: [Marcxml::ControlField.new("001", "\u0001")])
    error = assert_raises(Metacrunch::Error) { writer.write(bad, @ctx) }

    assert_match(/\Arecord at position 3 cannot be written as MARCXML: field 001: /, error.message)
  end

  def test_a_closed_pipe_raises_sigpipe_once
    writer = Writer.new(ClosedPipe.new)
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
    writer = Writer.new(path)

    assert_raises(Metacrunch::OutputError) { writer.open(nil) }
    assert_nil writer.close
    refute_path_exists path
  end

  def test_rejects_invalid_targets
    assert_raises(ArgumentError) { Writer.new(42) }
  end

  def test_refuses_names_it_cannot_write
    error = assert_raises(Metacrunch::OutputError) { open_writer(File.join(@dir, "out.xml.zst")) }

    assert_match(/cannot write zstd/, error.message)
  end

  private

  def record = Marcxml::Record.new(fields: [Marcxml::ControlField.new("001", "1")])

  def open_writer(target)
    writer = Writer.new(target)
    writer.open(nil)
    writer
  end

end
