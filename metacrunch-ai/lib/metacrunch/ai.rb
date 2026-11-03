# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "nokogiri"
require "net/http"
require "openssl"
require "time"
require "yaml"
require "metacrunch"
require_relative "ai/version"
require_relative "ai/errors"
require_relative "ai/http"
require_relative "ai/markdown"
require_relative "ai/html"
require_relative "ai/text"
require_relative "ai/extract"
require_relative "ai/tika"
require_relative "ai/chunk"
require_relative "ai/robots"
require_relative "ai/web"
require_relative "ai/open_ai"
require_relative "ai/fake_embedder"
require_relative "ai/embed"

module Metacrunch
  # AI steps for metacrunch: text from documents, and embeddings through
  # the OpenAI embeddings API and the servers that offer it.
  module Ai

    # The params of an embedder for jobs and commands, a group of
    # parameters: params { use Metacrunch::Ai::EMBEDDINGS_PARAMS } and
    # Metacrunch::Ai.embedder(params). The prefix keeps them apart from the
    # url and api_key of other groups; the key is a secret.
    EMBEDDINGS_PARAMS = proc do
      param :embeddings_url, String,
            desc: "embeddings API base URL (default: #{OpenAi::DEFAULT_URL}); fake or fake:DIMS for a fake embedder"
      param :embeddings_model, String, desc: "embedding model, e.g. text-embedding-3-small"
      secret :embeddings_api_key, String, desc: "API key, sent as a bearer token"
    end

    # The params that embedder reads, as EMBEDDINGS_PARAMS declares them.
    EMBEDDINGS_PARAM_NAMES = [:embeddings_url, :embeddings_model, :embeddings_api_key].freeze

    # embeddings_url fake or fake:DIMS
    FAKE = /\Afake(?::(\d+))?\z/

    # An embedder from the bound params of a job or command: an OpenAi, or
    # with embeddings_url fake a FakeEmbedder, which needs no network.
    # options go to OpenAi.new; the fake takes only max_inputs.
    def self.embedder(params, **options)
      url, model, api_key = EMBEDDINGS_PARAM_NAMES.map { params.public_send(it) if params.respond_to?(it) }
      return fake(url, options) if url&.start_with?("fake")
      unless text?(model)
        raise ArgumentError, "embeddings_model is required (or embeddings_url fake for a fake embedder)"
      end

      OpenAi.new(model:, url: url || OpenAi::DEFAULT_URL, api_key:, **options)
    end

    def self.fake(url, options)
      match = FAKE.match(url)
      raise ArgumentError, "embeddings_url #{url} is no fake; use fake or fake:DIMS, e.g. fake:384" unless match

      FakeEmbedder.new(dims: Integer(match[1] || "8", 10), **options.slice(:max_inputs))
    end
    private_class_method :fake

    # The params of a Tika server: params { use Metacrunch::Ai::TIKA_PARAMS }
    # and Metacrunch::Ai.tika(params).
    TIKA_PARAMS = proc do
      param :tika_url, String, desc: "Apache Tika server URL, e.g. http://localhost:9998"
    end

    # A Tika from the bound params of a job or command; options go to
    # Tika.new.
    def self.tika(params, **)
      url = params.tika_url if params.respond_to?(:tika_url)
      raise ArgumentError, "tika_url is required" unless text?(url)

      Tika.new(url:, **)
    end

    # Returns value if it is a positive Integer, else raises ArgumentError.
    def self.positive!(value, name)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
    end

    def self.text?(value) = value.is_a?(String) && !value.empty?

    # "1 text", "2 texts"
    def self.count(number, noun) = "#{number} #{number == 1 ? noun : "#{noun}s"}"

    # A non-empty Array of numbers.
    def self.vector?(value) = value.is_a?(Array) && !value.empty? && value.all?(Numeric)

    # Raises ArgumentError if texts are more than max_inputs.
    def self.max_inputs!(texts, max_inputs)
      return if texts.size <= max_inputs

      raise ArgumentError, "at most #{max_inputs} texts per call (max_inputs), got #{texts.size}"
    end

  end
end
