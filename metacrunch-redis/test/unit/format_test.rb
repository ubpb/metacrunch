# frozen_string_literal: true

require "test_helper"

class FormatTest < Minitest::Test

  Format = Metacrunch::Redis::Format

  def test_check_takes_json_and_string
    assert_equal [:json, :string], [Format.check!(:json), Format.check!(:string)]
  end

  def test_check_refuses_other_formats
    error = assert_raises(ArgumentError) { Format.check!(:yaml) }

    assert_equal "format must be :json or :string, got :yaml", error.message
  end

  def test_json_generates_records
    assert_equal(['{"isbn":"978","year":1866}', '["a",1]', '"text"', "null"],
                 [{"isbn" => "978", "year" => 1866}, ["a", 1], "text", nil].map { Format.encode(:json, it) })
  end

  def test_json_refuses_what_is_not_json
    [Set[1], Float::NAN, {"at" => Time.now}, "\xFF".b.force_encoding(Encoding::UTF_8)].each do |record|
      error = assert_raises(Metacrunch::Redis::Error) { Format.encode(:json, record) }

      assert_match(/\Arecord is not JSON \(#{record.class}\): /, error.message)
    end
  end

  def test_string_writes_strings_as_they_are
    assert_equal "<record/>", Format.encode(:string, "<record/>")
  end

  def test_string_refuses_other_records
    error = assert_raises(Metacrunch::Redis::Error) { Format.encode(:string, {"a" => 1}) }

    assert_equal "record is a Hash, not a String (format: :string)", error.message
  end

  def test_json_parses_entries
    assert_equal([{"isbn" => "978"}, "text", 1], ['{"isbn":"978"}', '"text"', "1"].map { Format.decode(:json, it) })
  end

  def test_json_yields_an_invalid_entry_as_an_invalid_record
    record = Format.decode(:json, "{not json")

    assert_kind_of Metacrunch::InvalidRecord, record
    assert_equal "{not json", record.raw
    assert_kind_of JSON::ParserError, record.error
  end

  def test_json_refuses_duplicate_keys
    assert_kind_of Metacrunch::InvalidRecord, Format.decode(:json, '{"a":1,"a":2}')
  end

  def test_json_yields_invalid_utf8_as_an_invalid_record_with_the_raw_given
    record = Format.decode(:json, "\"\xFF\"".b, raw: {"key" => "k"})

    assert_equal [{"key" => "k"}, "invalid UTF-8"], [record.raw, record.error.message]
  end

  def test_string_yields_entries_as_they_are
    entry = "\xFF".b

    assert_same entry, Format.decode(:string, entry)
  end

end
