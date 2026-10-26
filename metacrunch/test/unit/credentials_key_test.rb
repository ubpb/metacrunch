# frozen_string_literal: true

require "test_helper"

class CredentialsKeyTest < Minitest::Test

  Key = Metacrunch::Credentials::Key
  HEX = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

  def test_generates_32_random_bytes
    first = Key.generate
    second = Key.generate

    assert_equal 32, first.bytes.bytesize
    refute_equal first.bytes, second.bytes
    assert_match(/\A\h{64}\z/, first.hex)
  end

  def test_parses_hex_with_surrounding_whitespace_and_upper_case
    assert_equal HEX, Key.parse("  #{HEX.upcase}\r\n", source: "master.key").hex
  end

  def test_rejects_anything_but_64_hex_characters
    texts = ["", HEX[1..], "#{HEX}0", HEX.sub("0", "g"), "#{HEX[0, 32]} #{HEX[32..]}"]
    messages = texts.map do |text|
      assert_raises(Metacrunch::CredentialsError) { Key.parse(text, source: "METACRUNCH_MASTER_KEY") }.message
    end

    assert_equal ["invalid key from METACRUNCH_MASTER_KEY: expected 64 hex characters"], messages.uniq
  end

  def test_inspect_and_to_s_name_the_source_but_never_the_key
    key = Key.parse(HEX, source: "/p/.metacrunch/master.key")

    assert_equal "#<Metacrunch::Credentials::Key from /p/.metacrunch/master.key>", key.inspect
    refute_includes key.to_s, HEX
  end

end
