# frozen_string_literal: true

require "test_helper"
require "timeout"

class MarcEachTest < Minitest::Test

  include Fixtures

  COLLECTIONS = ["collection.xml", "collection.mrc", "collection.jsonl"].freeze
  IDS = ["book-1", "article-1", "holding-1"].freeze

  def test_each_reads_every_format_from_a_string
    COLLECTIONS.each do |name|
      records = []

      assert_nil Metacrunch::Marc.each(fixture(name)) { records << it }
      assert_equal IDS, ids(records), name
    end
  end

  def test_each_reads_every_format_from_a_file
    COLLECTIONS.each do |name|
      File.open(fixture_path(name), "rb") do |file|
        assert_equal IDS, ids(Metacrunch::Marc.each(file)), name
      end
    end
  end

  def test_each_reads_a_gzip_stream
    gzip = Zlib.gzip(fixture("collection.mrc"))

    assert_equal IDS, ids(Metacrunch::Marc.each(Zlib::GzipReader.new(StringIO.new(gzip))))
  end

  # Detection reads ahead; every byte it read must still reach the parser.
  def test_each_reads_inputs_that_give_their_bytes_in_pieces
    COLLECTIONS.each do |name|
      content = fixture(name)

      [Inputs::Trickle.new(content), Inputs::Chunked.new(content, 5), Inputs::ReadOnly.new(content)].each do |input|
        assert_equal IDS, ids(Metacrunch::Marc.each(input)), "#{name}, #{input.class}"
      end
    end
  end

  # Detection must not wait for more bytes than the first record has.
  def test_each_gives_the_first_record_of_a_pausing_pipe_at_once
    reader, writer = IO.pipe
    writer.write(%({"fields":[{"001":"1"}]}\n))

    assert_equal "1", Timeout.timeout(5) { Metacrunch::Marc.each(reader).first["001"].value }
  ensure
    writer&.close
    reader&.close
  end

  # Some IO-like objects return "" instead of nil at their end.
  def test_each_ends_at_an_empty_read
    input = Object.new
    io = StringIO.new(" \n")
    input.define_singleton_method(:read) { |length| io.read(length) || "" }

    assert_empty Timeout.timeout(5) { Metacrunch::Marc.each(input).to_a }
  end

  def test_each_raises_at_the_first_record_that_cannot_be_read
    records = []
    input = StringIO.new("#{fixture("collection.jsonl")}{\"fields\": 3}\n")

    assert_raises(Metacrunch::Marc::ParseError) { Metacrunch::Marc.each(input) { records << it } }
    assert_equal IDS, ids(records)
  end

  # The record is shorter than the bytes detection asks for, so detection
  # reaches the end of the input.
  def test_each_does_not_read_again_after_the_end
    iso = "00026nam a2200025 c 4500\x1E\x1D"

    assert_equal ["00026nam a2200025 c 4500"], Metacrunch::Marc.each(Inputs::EndOnce.new(iso)).map(&:leader)
  end

  def test_each_skips_a_byte_order_mark_and_whitespace
    ["collection.mrc", "collection.jsonl"].each do |name|
      content = "\uFEFF\n  #{fixture(name)}"

      assert_equal IDS, ids(Metacrunch::Marc.each(content)), name
      assert_equal IDS, ids(Metacrunch::Marc.each(StringIO.new(content))), name
    end
    assert_equal IDS, ids(Metacrunch::Marc.each(StringIO.new("\uFEFF#{fixture("collection.xml")}")))
  end

  def test_each_yields_nothing_for_input_without_a_record
    ["", " \n\t", StringIO.new(""), StringIO.new("\uFEFF\n \0")].each do |input|
      assert_empty Metacrunch::Marc.each(input).to_a
    end
  end

  def test_each_normalizes
    json = %({"fields": [{"001": "Mu\u0308ller"}]}\n)

    assert_equal(["Müller"], Metacrunch::Marc.each(StringIO.new(json), normalize: :nfc).map { it["001"].value })
  end

  def test_each_rejects_other_formats
    {
      "id;title\n1;x\n" => %(neither MARCXML, ISO 2709 nor MARC-in-JSON: it starts with "id;title\\n1;x\\n"),
      %([{"fields": []}]) => "a JSON array of records; convert it to one record per line first, e.g. " \
                             "jq -c '.[]' in.json > out.jsonl"
    }.each do |content, message|
      [content, StringIO.new(content)].each do |input|
        error = assert_raises(Metacrunch::Marc::ParseError) { Metacrunch::Marc.each(input) { nil } }

        assert_equal message, error.message
      end
    end
  end

  def test_each_reads_nothing_before_the_enumerator_is_used
    io = StringIO.new("id;title\n")
    enum = Metacrunch::Marc.each(io)

    assert_equal 0, io.pos
    assert_raises(Metacrunch::Marc::ParseError) { enum.first }
  end

  def test_each_rejects_invalid_arguments_at_once
    assert_raises(ArgumentError) { Metacrunch::Marc.each(nil) }
    assert_raises(ArgumentError) { Metacrunch::Marc.each(Object.new) }
    assert_raises(ArgumentError) { Metacrunch::Marc.each("", normalize: :nfd) }
  end

  private

  def ids(records) = records.map { it["001"].value }

end
