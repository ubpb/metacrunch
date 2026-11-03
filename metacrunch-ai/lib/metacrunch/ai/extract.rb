# frozen_string_literal: true

module Metacrunch
  module Ai
    # A step that turns a document's content into text: map Extract.new(...)
    # with extractors, e.g. Html.new, Text.new, Tika.new(url: ...).
    #
    # An extractor has types (MIME types, or nil for any) and
    # extract(content, type:), which returns {text:, title:, lang:} (text a
    # String, or an Array of page Strings) and may add fields: (a Hash of
    # further fields, e.g. from front matter) and mark:, set on the record;
    # optional open(context) and close.
    #
    # The step takes the content from the field from: and the MIME type from
    # type:, asks the first extractor that takes the type (a record without
    # a type, the first one), merges the fields of the extractor into the
    # record (they win over its fields), writes the text into into: and
    # title and lang
    # into the fields title: and lang: (nil turns them off; an existing value
    # is only replaced by a found one), and removes the content, so its
    # bytes are not copied further. A record without content or text passes
    # with the mark "No text extracted".
    class Extract

      NO_TEXT = "No text extracted"

      def initialize(*extractors, from: "content", type: "type", into: "text", title: "title", lang: "lang")
        raise ArgumentError, "Extract needs at least one extractor" if extractors.empty?

        extractors.each do |extractor|
          next if extractor.respond_to?(:extract)

          raise ArgumentError, "an extractor must respond to extract, got #{extractor.inspect}"
        end
        {from:, type:, into:}.each { |name, value| field!(name, value) }
        {title:, lang:}.each { |name, value| field!(name, value) unless value.nil? }

        @extractors = extractors
        @from = from
        @type = type
        @into = into
        @title = title
        @lang = lang
      end

      def open(context) = @extractors.each { it.open(context) if it.respond_to?(:open) }

      def close = @extractors.each { it.close if it.respond_to?(:close) }

      def call(record, ctx)
        raise ContractError, "Extract needs Hash records, got #{record.class}" unless record.is_a?(Hash)

        result = extract(record[@from], media_type(record[@type]))
        record = record.except(@from).merge(result[:fields] || {}, @into => result[:text])
        record[@title] = result[:title] if @title && result[:title]
        record[@lang] = result[:lang] if @lang && result[:lang]
        ctx.mark(result[:mark]) if result[:mark]
        ctx.mark(NO_TEXT) if blank?(result[:text])
        record
      end

      private

      def field!(name, value)
        return if Ai.text?(value)

        raise ArgumentError, "#{name} must be a non-empty String, got #{value.inspect}"
      end

      def extract(content, type)
        return {text: ""} if content.nil?

        extractor = extractor_for(type)
        result = extractor.extract(content, type:)
        text = result[:text] if result.is_a?(Hash)
        unless text.is_a?(String) || text.is_a?(Array)
          raise Error, "#{extractor.class} gave no text: #{(text || result).inspect}"
        end
        unless result[:fields].nil? || result[:fields].is_a?(Hash)
          raise Error, "#{extractor.class} gave fields that are no Hash: #{result[:fields].inspect}"
        end

        result
      end

      def extractor_for(type)
        return @extractors.first if type.nil?

        @extractors.find { it.types.nil? || it.types.include?(type) } or raise Error, "no extractor for #{type}"
      end

      # The MIME type without parameters, in lower case; nil without one.
      def media_type(value)
        type = value.to_s.split(";").first.to_s.strip.downcase
        type unless type.empty?
      end

      def blank?(text) = Array(text).all? { it.to_s.strip.empty? }

    end
  end
end
