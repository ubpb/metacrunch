# frozen_string_literal: true

module Metacrunch
  module Ai
    # A step that adds the vector of a record's text: map Embed.new(...),
    # best with batch:, so that a provider call takes many texts.
    #
    # provider: an object with embed(texts) that returns a vector (an Array
    # of numbers) per text; optional open(context), close, max_inputs (the
    # most texts per call) and stats (a Hash; "tokens" goes into the log).
    # text: a field, an Array of fields, or a callable that returns the text
    # of a record or nil. into: the field that gets the vector.
    class Embed

      NO_TEXT = "No text to embed"
      PROBE = "metacrunch"

      # The dimension of the vectors, from the probe in open.
      attr_reader :dims

      def initialize(provider, text:, into: "embedding")
        unless provider.respond_to?(:embed)
          raise ArgumentError, "provider must respond to embed, got #{provider.inspect}"
        end
        raise ArgumentError, "into must be a non-empty String, got #{into.inspect}" unless Ai.text?(into)

        @provider = provider
        @text = text_option(text)
        @into = into
        @texts = 0
        @calls = 0
      end

      # Opens the provider and embeds PROBE once, so a wrong key, model or
      # URL stops the job before records are read.
      def open(context)
        @logger = context.logger
        @provider.open(context) if @provider.respond_to?(:open)
        probe = @provider.embed([PROBE])
        vector = probe.first if probe.is_a?(Array) && probe.size == 1
        raise Error, "the provider gave no vector for the probe" unless usable?(vector)

        @dims = vector.size
      end

      def close
        @logger&.info(summary)
        @provider.close if @provider.respond_to?(:close)
      end

      def call(record, ctx)
        result = call_batch([record], [ctx]).first
        raise result if result.is_a?(Exception)

        result
      end

      # One result per record: the record with its vector, the record
      # unchanged (no text, with a mark), or the error it fails with.
      def call_batch(records, ctxs)
        results = Array.new(records.size)
        pending = []
        records.each_with_index do |record, index|
          text = text_of(record)
        rescue ContractError => e
          results[index] = e
        else
          text ? pending << [index, text] : results[index] = unmarked(record, ctxs[index])
        end
        pending.each_slice(max_inputs(pending.size)) { embed_slice(it, records, results) }
        results
      end

      private

      def text_option(text)
        return [text] if Ai.text?(text)
        return text if text.is_a?(Array) && !text.empty? && text.all? { Ai.text?(it) }
        return text if text.respond_to?(:call)

        raise ArgumentError, "text must be a field, an Array of fields or a callable, got #{text.inspect}"
      end

      def text_of(record)
        return fields_text(record) if @text.is_a?(Array)

        text = @text.call(record)
        unless text.nil? || text.is_a?(String)
          raise ContractError, "text: returned #{text.class}, expected a String or nil"
        end

        text unless text.nil? || text.strip.empty?
      end

      def fields_text(record)
        raise ContractError, "Embed needs Hash records for text: fields, got #{record.class}" unless record.is_a?(Hash)

        parts = @text.flat_map { Array(record[it]) }.map(&:to_s).reject { it.strip.empty? }
        parts.join("\n") unless parts.empty?
      end

      def unmarked(record, ctx)
        ctx.mark(NO_TEXT)
        record
      end

      def max_inputs(fallback) = @provider.respond_to?(:max_inputs) ? @provider.max_inputs : [fallback, 1].max

      # Embeds the texts of slice ([index, text] pairs) and sets the results
      # of their records. Refused input is sent again text by text, so only
      # the texts at fault fail; other errors fail every record of the call.
      def embed_slice(slice, records, results)
        vectors = embed(slice.map(&:last))
      rescue InvalidInput => e
        return results[slice.first.first] = e if slice.one?

        slice.each { embed_slice([it], records, results) }
      rescue StandardError => e
        slice.each { results[it.first] = e }
      else
        slice.zip(vectors) { |(index, _text), vector| results[index] = with_vector(records[index], vector) }
      end

      def embed(texts)
        vectors = @provider.embed(texts)
        unless vectors.is_a?(Array) && vectors.size == texts.size
          count = vectors.is_a?(Array) ? vectors.size : 0
          raise Error, "the provider returned #{Ai.count(count, "vector")} for #{Ai.count(texts.size, "text")}"
        end

        @calls += 1
        @texts += texts.size
        vectors
      end

      def with_vector(record, vector)
        return Error.new("vector with a non-finite number or not an Array of numbers") unless usable?(vector)
        return Error.new("vector of #{vector.size} dimensions, expected #{@dims}") if @dims && vector.size != @dims

        record.merge(@into => vector)
      end

      def usable?(vector) = Ai.vector?(vector) && vector.all?(&:finite?)

      def summary
        tokens = @provider.stats["tokens"] if @provider.respond_to?(:stats)
        "embedded #{Ai.count(@texts, "text")} in #{Ai.count(@calls, "call")}#{", #{tokens} tokens" if tokens}"
      end

    end
  end
end
