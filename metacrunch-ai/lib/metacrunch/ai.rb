# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "time"
require "metacrunch"
require_relative "ai/version"
require_relative "ai/errors"
require_relative "ai/http"
require_relative "ai/open_ai"
require_relative "ai/fake_embedder"
require_relative "ai/embed"

module Metacrunch
  # AI steps for metacrunch: embeddings through the OpenAI embeddings API
  # and the servers that offer it.
  module Ai

    # Returns value if it is a positive Integer, else raises ArgumentError.
    def self.positive!(value, name)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
    end

    def self.text?(value) = value.is_a?(String) && !value.empty?

    # A non-empty Array of numbers.
    def self.vector?(value) = value.is_a?(Array) && !value.empty? && value.all?(Numeric)

    # Raises ArgumentError if texts are more than max_inputs.
    def self.max_inputs!(texts, max_inputs)
      return if texts.size <= max_inputs

      raise ArgumentError, "at most #{max_inputs} texts per call (max_inputs), got #{texts.size}"
    end

  end
end
