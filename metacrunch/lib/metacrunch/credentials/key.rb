# frozen_string_literal: true

require "securerandom"

module Metacrunch
  module Credentials
    # A 256-bit key. source says where it came from (METACRUNCH_MASTER_KEY
    # or the path of a key file), for messages; inspect never shows the key.
    class Key

      HEX = /\A\h{64}\z/

      attr_reader :bytes, :source

      def self.generate(source: "a new key") = new(SecureRandom.random_bytes(32), source:)

      # Parses 64 hex characters; whitespace around them is ignored.
      def self.parse(text, source:)
        hex = text.b.strip
        raise CredentialsError, "invalid key from #{source}: expected 64 hex characters" unless HEX.match?(hex)

        new([hex].pack("H*"), source:)
      end

      def initialize(bytes, source:)
        @bytes = bytes.b.freeze
        @source = source
        freeze
      end

      def hex = bytes.unpack1("H*")

      def inspect = "#<#{self.class.name} from #{source}>"

    end
  end
end
