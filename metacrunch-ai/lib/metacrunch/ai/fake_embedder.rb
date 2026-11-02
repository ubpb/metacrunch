# frozen_string_literal: true

module Metacrunch
  module Ai
    # An embedder without network, for tests of jobs and dry runs: every
    # text gets a unit vector of dims numbers made from its SHA-256, the
    # same in every process and run.
    class FakeEmbedder

      attr_reader :dims, :max_inputs

      def initialize(dims: 8, max_inputs: 32)
        @dims = Ai.positive!(dims, "dims")
        @max_inputs = Ai.positive!(max_inputs, "max_inputs")
        @requests = 0
      end

      def embed(texts)
        Ai.max_inputs!(texts, @max_inputs)
        @requests += 1
        texts.map { vector(it) }
      end

      def stats = {"requests" => @requests}

      private

      # The digest's bytes, repeated to dims, as numbers from -1 to 1,
      # scaled to length 1. A zero vector would need 32 zero bytes.
      def vector(text)
        bytes = Digest::SHA256.digest(text).bytes
        numbers = Array.new(@dims) { (bytes[it % bytes.size] / 127.5) - 1.0 }
        length = Math.sqrt(numbers.sum { it * it })
        numbers.map { it / length }
      end

    end
  end
end
