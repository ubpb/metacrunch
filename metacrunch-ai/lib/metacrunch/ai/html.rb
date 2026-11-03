# frozen_string_literal: true

module Metacrunch
  module Ai
    # An extractor for HTML: the main content of a page as Markdown, with
    # the page's title and language.
    #
    # content: a CSS selector for the main content (all matches, in document
    # order); without one, or when it matches nothing, the first of <main>,
    # [role=main], a single <article> and <body>. Inside the content,
    # scripts, navigation, forms and hidden elements are removed, with
    # <body> also its header, footer and aside; remove: a CSS selector for
    # more.
    class Html

      TYPES = ["text/html", "application/xhtml+xml"].freeze
      NOISE = "script, style, noscript, template, nav, form, iframe, svg, [hidden], [aria-hidden=true]"
      PAGE_NOISE = "header, footer, aside"

      def initialize(content: nil, remove: nil)
        @content = selector(content, "content")
        @remove = selector(remove, "remove")
      end

      def types = TYPES

      # content: the page as bytes (charset from a BOM or <meta charset>) or
      # as a String (its encoding). Takes type: as every extractor does.
      def extract(content, **)
        document = Nokogiri::HTML5(content.to_s)
        roots, page = main(document)
        roots.each { clean(it, page) }
        text = roots.map { Markdown.convert(it) }.reject(&:empty?).join("\n\n")
        {text: text.scrub, title: title(document), lang: present(document.root&.[]("lang"))}
      end

      private

      def selector(value, name)
        return nil if value.nil?
        raise ArgumentError, "#{name} must be a CSS selector, got #{value.inspect}" unless value.is_a?(String)

        Nokogiri::HTML5("").css(value)
        value
      rescue Nokogiri::CSS::SyntaxError => e
        raise ArgumentError, "#{name} is no valid CSS selector: #{value.inspect} (#{e.message.lines.first.strip})"
      end

      # The roots of the main content, and whether it is the whole page.
      def main(document)
        matches = @content ? document.css(@content).to_a : []
        return [matches.reject { |match| match.ancestors.any? { matches.include?(it) } }, false] unless matches.empty?

        found = document.at_css("main") || document.at_css("[role=main]") || single(document.css("article"))
        return [[found], false] if found

        [[document.at_css("body")].compact, true]
      end

      def single(nodes) = nodes.size == 1 ? nodes.first : nil

      def clean(root, page)
        root.css(NOISE).each(&:remove)
        root.css(PAGE_NOISE).each(&:remove) if page
        root.css(@remove).each(&:remove) if @remove
      end

      def title(document)
        present(document.at_css("title")&.text) || present(document.at_css("h1")&.text)
      end

      def present(text)
        text = text&.gsub(/[[:space:]]+/, " ")&.strip
        text unless text.nil? || text.empty?
      end

    end
  end
end
