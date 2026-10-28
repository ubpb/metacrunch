# frozen_string_literal: true

require "test_helper"

module KeysTests

  def test_records_written_under_template_keys_read_back_by_pattern
    books = [{"isbn" => "1", "title" => "A"}, {"isbn" => "2", "title" => "B"}]
    write(books, key: "#{key("book:")}%{isbn}")
    records = read("#{key("book:")}*")

    assert_equal [key("book:1"), key("book:2")], records.map { it["key"] }.sort
    assert_equal(books, records.sort_by { it["key"] }.map { it["value"] })
  end

  def test_expire_sets_a_time_to_live
    write([{"isbn" => "1"}], key: "#{key("book:")}%{isbn}", expire: 60)

    assert_includes 1..60, redis.call("TTL", key("book:1"))
  end

  def test_a_callable_action_deletes
    prefix = key("book:")
    write([{"isbn" => "1"}, {"isbn" => "2"}], key: "#{prefix}%{isbn}")
    write([{"isbn" => "1", "deleted" => true}], key: "#{prefix}%{isbn}",
                                                action: ->(book) { book["deleted"] ? :delete : :set })

    assert_equal([key("book:2")], read("#{prefix}*").map { it["key"] })
  end

  def test_the_reader_skips_keys_of_other_types
    redis.call("RPUSH", key("book:queue"), "x")
    redis.call("SET", key("book:1"), "1")

    assert_equal [{"key" => key("book:1"), "value" => 1}], read("#{key("book:")}*", fetch: 1)
  end

  private

  def write(records, **)
    writer = Metacrunch::Redis::KeyWriter.new(connection, **)
    writer.open(context)
    writer.write_batch(records)
  ensure
    writer&.close
  end

  def read(match, **)
    reader = Metacrunch::Redis::KeyReader.new(connection, match:, **)
    reader.open(context)
    reader.each.to_a
  ensure
    reader&.close
  end

end

Integration.define("Keys", KeysTests)
