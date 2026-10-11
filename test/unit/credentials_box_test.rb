# frozen_string_literal: true

require "test_helper"

class CredentialsBoxTest < Minitest::Test

  Box = Metacrunch::Credentials::Box
  Key = Metacrunch::Credentials::Key
  PATH = "/p/.metacrunch/credentials.yml.enc"
  NOT_CREDENTIALS = "not a metacrunch credentials file: #{PATH}".freeze

  REJECTED = {
    "" => NOT_CREDENTIALS,
    "a: 1\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\nnot base64!\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\nc2hvcnQ=\n" => NOT_CREDENTIALS,
    "metacrunch credentials v1\nAAAA\nAAAA\n" => NOT_CREDENTIALS,
    "metacrunch credentials v2\nAAAA\n" => "unsupported credentials format in #{PATH}: v2"
  }.freeze

  def setup
    @key = Key.generate
  end

  def test_unseals_what_it_sealed_as_utf8
    plaintext = Box.unseal(Box.seal("catalog:\n  api_key: pässwörd\n", @key), @key, path: PATH)

    assert_equal "catalog:\n  api_key: pässwörd\n", plaintext
    assert_equal Encoding::UTF_8, plaintext.encoding
  end

  def test_seals_empty_text
    assert_equal "", Box.unseal(Box.seal("", @key), @key, path: PATH)
  end

  def test_writes_a_header_and_one_line_of_base64
    header, body, *rest = Box.seal("a: 1\n", @key).lines(chomp: true)

    assert_equal ["metacrunch credentials v1", []], [header, rest]
    assert_match(%r{\A[A-Za-z0-9+/]+=*\z}, body)
  end

  def test_every_seal_uses_a_new_iv
    refute_equal Box.seal("a: 1\n", @key), Box.seal("a: 1\n", @key)
  end

  def test_a_wrong_key_fails_and_names_its_source
    content = Box.seal("a: 1\n", @key)
    other = Key.generate(source: "METACRUNCH_MASTER_KEY")
    error = assert_raises(Metacrunch::CredentialsError) { Box.unseal(content, other, path: PATH) }

    assert_equal "cannot decrypt #{PATH}: wrong key or modified file (key from METACRUNCH_MASTER_KEY)", error.message
  end

  def test_a_changed_byte_in_iv_tag_or_ciphertext_fails
    header, body = Box.seal("a: 1\n", @key).lines(chomp: true)
    raw = body.unpack1("m0")
    failures = [0, 12, 28].count do |index|
      changed = raw.dup
      changed.setbyte(index, changed.getbyte(index) ^ 1)
      Box.unseal("#{header}\n#{[changed].pack("m0")}\n", @key, path: PATH)
      false
    rescue Metacrunch::CredentialsError
      true
    end

    assert_equal 3, failures
  end

  def test_rejects_content_that_is_no_credentials_file
    REJECTED.each do |content, message|
      error = assert_raises(Metacrunch::CredentialsError) { Box.unseal(content, @key, path: PATH) }

      assert_equal message, error.message, content.inspect
    end
  end

  def test_reads_crlf_line_ends_and_trailing_blank_lines
    content = "#{Box.seal("a: 1\n", @key).gsub("\n", "\r\n")}\r\n\r\n"

    assert_equal "a: 1\n", Box.unseal(content, @key, path: PATH)
  end

end
