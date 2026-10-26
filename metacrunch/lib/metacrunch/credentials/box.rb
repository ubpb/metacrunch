# frozen_string_literal: true

require "openssl"

module Metacrunch
  module Credentials
    # File format v1: a header line and the strict Base64 of IV, tag and
    # ciphertext. AES-256-GCM with the header as authenticated data, so a
    # wrong key and every changed byte fail.
    module Box

      HEADER = "metacrunch credentials v1"
      HEADER_PREFIX = "metacrunch credentials "
      CIPHER = "aes-256-gcm"
      IV_LENGTH = 12
      TAG_LENGTH = 16

      module_function

      # The file content for plaintext, with a new random IV.
      def seal(plaintext, key)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = key.bytes
        iv = cipher.random_iv
        cipher.auth_data = HEADER
        ciphertext = cipher.update(plaintext.b) + cipher.final
        "#{HEADER}\n#{[iv + cipher.auth_tag + ciphertext].pack("m0")}\n"
      end

      # The plaintext (UTF-8) in file content. path names the file in errors.
      def unseal(content, key, path:)
        raw = payload(content.b, path)
        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = key.bytes
        cipher.iv = raw.byteslice(0, IV_LENGTH)
        cipher.auth_tag = raw.byteslice(IV_LENGTH, TAG_LENGTH)
        cipher.auth_data = HEADER
        plaintext = cipher.update(raw.byteslice((IV_LENGTH + TAG_LENGTH)..)) + cipher.final
        plaintext.force_encoding(Encoding::UTF_8)
      rescue OpenSSL::Cipher::CipherError
        raise CredentialsError, "cannot decrypt #{path}: wrong key or modified file (key from #{key.source})"
      end

      # IV, tag and ciphertext as one binary String. CRLF line ends and
      # trailing blank lines are accepted.
      def payload(content, path)
        lines = content.lines(chomp: true)
        lines.pop while lines.last&.strip&.empty?
        header, body = lines
        check_header!(header, path)
        raw = lines.size == 2 ? body.strip.unpack1("m0") : ""
        raise not_credentials(path) if raw.bytesize < IV_LENGTH + TAG_LENGTH

        raw
      rescue ArgumentError
        raise not_credentials(path)
      end

      def check_header!(header, path)
        return if header == HEADER
        raise not_credentials(path) unless header&.start_with?(HEADER_PREFIX)

        raise CredentialsError, "unsupported credentials format in #{path}: #{header.delete_prefix(HEADER_PREFIX)}"
      end

      def not_credentials(path) = CredentialsError.new("not a metacrunch credentials file: #{path}")

    end
  end
end
