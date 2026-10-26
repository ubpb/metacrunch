# frozen_string_literal: true

require "test_helper"

class Iso2709EachTest < Minitest::Test

  include Inputs
  include Iso

  Marc = Metacrunch::Marc
  Iso2709 = Metacrunch::Marc::Iso2709

  def test_each_raw_yields_records_with_their_terminator
    raws = Iso2709.each_raw(book("1") + book("2")).to_a

    assert_equal [book("1"), book("2")], raws.map(&:b)
    assert(raws.all? { it.encoding == Encoding::UTF_8 })
  end

  def test_skips_line_breaks_spaces_tabs_and_nul_between_records
    input = ["\n", book("1"), "\r\n", book("2"), " \t", book("3"), "\0\0\0", "\n"].join

    assert_equal(["1", "2", "3"], Iso2709.each(input).map { it["001"].value })
  end

  def test_skips_a_byte_order_mark_at_the_start
    assert_equal(["1"], Iso2709.each("\xEF\xBB\xBF#{book}".b).map { it["001"].value })
  end

  # cat a.mrc b.mrc, where both files start with one.
  def test_skips_byte_order_marks_of_concatenated_files
    input = "\xEF\xBB\xBF#{book("1")}\n\xEF\xBB\xBF#{book("2")}".b

    assert_equal(["1", "2"], Iso2709.each(input).map { it["001"].value })
  end

  def test_skips_record_terminators_without_a_record
    input = "#{book("1")}\x1D\n\x1D#{book("2")}".b

    assert_equal(["1", "2"], Iso2709.each(input).map { it["001"].value })
  end

  def test_a_record_cut_off_by_the_end_of_the_input
    input = book("1") + book("2").byteslice(0, 30)

    assert_equal [book("1"), book("2").byteslice(0, 30)], Iso2709.each_raw(input).map(&:b)
    assert_equal "the input ended inside a record", assert_raises(Marc::ParseError) { Iso2709.each(input).to_a }.message
  end

  def test_records_cut_by_chunk_boundaries
    input = Array.new(200) { book(it.to_s) }.join

    assert_equal Iso2709.each_raw(input).to_a, Iso2709.each_raw(Trickle.new(input)).to_a
    assert_equal 200, Iso2709.each_raw(ReadOnly.new(input)).count
  end

  def test_records_over_99999_bytes
    fields = [["001", "big"]] + Array.new(12) { ["500", "  \x1Fa#{"x" * 9_000}"] }
    big = raw(*fields)

    assert_equal "99999", big.byteslice(0, 5)
    assert_equal(["big", "1"], Iso2709.each(StringIO.new(big + book)).map { it["001"].value })
  end

  def test_each_without_a_block_is_an_enumerator
    assert_equal(["1", "2"], Iso2709.each(book("1") + book("2")).map { it["001"].value })
  end

  def test_normalize
    assert_equal "Müller", Iso2709.each(raw(["001", "Mu\u0308ller"]), normalize: :nfc).first["001"].value
  end

  def test_rejects_invalid_arguments
    assert_raises(ArgumentError) { Iso2709.each_raw(nil) }
    assert_raises(ArgumentError) { Iso2709.each(nil) }
    assert_raises(ArgumentError) { Iso2709.each(book, normalize: :nfd) }
  end

end
