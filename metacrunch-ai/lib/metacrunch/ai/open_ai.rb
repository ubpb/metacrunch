# frozen_string_literal: true

module Metacrunch
  module Ai
    # An embedder for the OpenAI embeddings API (POST {url}/embeddings),
    # which many servers offer: OpenAI, Azure OpenAI, Voyage, Mistral,
    # Hugging Face TEI, Ollama, vLLM. body: further request fields, e.g.
    # dimensions or input_type; headers: further headers, e.g. Azure's
    # api-key.
    class OpenAi

      DEFAULT_URL = "https://api.openai.com/v1"

      attr_reader :model, :url, :max_inputs

      def initialize(model:, url: DEFAULT_URL, api_key: nil, headers: {}, body: {}, max_inputs: 32, timeout: 60,
                     retries: 5)
        raise ArgumentError, "model must be a non-empty String, got #{model.inspect}" unless Ai.text?(model)
        unless api_key.nil? || api_key.is_a?(String)
          raise ArgumentError, "api_key must be a String, got #{api_key.class}"
        end
        raise ArgumentError, "body must be a Hash, got #{body.inspect}" unless body.is_a?(Hash)
        raise ArgumentError, "headers must be a Hash, got #{headers.inspect}" unless headers.is_a?(Hash)

        @model = model
        @url = url
        @body = body.transform_keys(&:to_s)
        @max_inputs = Ai.positive!(max_inputs, "max_inputs")
        authorization = api_key ? {"Authorization" => "Bearer #{api_key}"} : {}
        @http = Http.new(url:, headers: authorization.merge(headers), timeout:, retries:, name: "embeddings")
        @requests = 0
        @tokens = nil
      end

      # context: the OpenContext of the step, for its logger.
      def open(context = nil)
        @http.open(context&.logger)
      end

      def close = @http.close

      # The vectors of texts, in their order: Arrays of Floats.
      def embed(texts)
        Ai.max_inputs!(texts, @max_inputs)
        answer = @http.post_json("/embeddings", @body.merge("model" => @model, "input" => texts))
        @requests += 1
        count_tokens(answer["usage"])
        vectors(answer, texts.size)
      end

      # Requests, and the tokens the service reported, if it did.
      def stats = {"requests" => @requests, "tokens" => @tokens}.compact

      def inspect = "#<#{self.class.name} model=#{@model.inspect} url=#{@url.inspect}>"

      private

      def count_tokens(usage)
        return unless usage.is_a?(Hash)

        tokens = usage["prompt_tokens"] || usage["total_tokens"]
        @tokens = (@tokens || 0) + tokens if tokens.is_a?(Integer)
      end

      def vectors(answer, count)
        data = answer["data"]
        malformed("no data") unless data.is_a?(Array)
        malformed("#{Ai.count(data.size, "vector")} for #{Ai.count(count, "text")}") unless data.size == count

        embeddings(data, count).map { vector(it) }
      end

      # The embeddings by index, or in the order of the answer where no
      # entry has an index, as some servers send them.
      def embeddings(data, count)
        return data.map { it["embedding"] if it.is_a?(Hash) } if data.none? { it.is_a?(Hash) && it.key?("index") }

        by_index = data.filter_map { [it["index"], it["embedding"]] if it.is_a?(Hash) }.to_h
        Array.new(count) { by_index[it] }
      end

      def vector(embedding)
        malformed("an embedding is missing or not an Array of numbers") unless Ai.vector?(embedding)

        embedding.map(&:to_f)
      end

      def malformed(what)
        raise ApiError, "embeddings at #{@url.to_s.chomp("/")}/embeddings: malformed answer, #{what}"
      end

    end
  end
end
