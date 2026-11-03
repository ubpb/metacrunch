# frozen_string_literal: true

module Metacrunch
  module Ai
    # HTML to lean Markdown, for text that is chunked and embedded: headings,
    # paragraphs, lists, tables, code blocks and quotes keep their structure;
    # inline elements give their text only (no link targets, no emphasis),
    # and an image gives its alt text when it stands alone. Internal; Html
    # and Tika use it.
    module Markdown

      SKIP = ["head", "script", "style", "template", "noscript"].freeze
      BLOCKS = [
        "address", "article", "aside", "blockquote", "body", "dd", "details", "dialog", "div", "dl", "dt", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "html",
        "li", "main", "nav", "ol", "p", "pre", "section", "summary", "table", "ul"
      ].freeze
      HEADINGS = ["h1", "h2", "h3", "h4", "h5", "h6"].freeze
      CELLS = ["td", "th"].freeze
      # Stands for a line break in inline text until whitespace is collapsed.
      BREAK = ""

      module_function

      # Parses HTML with Nokogiri's HTML5 parser; a document nested deeper
      # than the parser allows raises InvalidInput.
      def parse(html)
        Nokogiri::HTML5(html)
      rescue ArgumentError => e
        raise InvalidInput, "the HTML cannot be parsed: #{e.message}"
      end

      # node: a Nokogiri node, e.g. a document or its body.
      def convert(node) = blocks(node).join("\n\n")

      # The Markdown blocks of node's children: runs of inline content become
      # paragraphs, block elements their blocks.
      def blocks(node)
        result = []
        run = []
        node.children.each do |child|
          next if skip?(child)

          if block?(child)
            result << paragraph(run)
            run = []
            result.concat(block(child))
          else
            run << child
          end
        end
        result << paragraph(run)
        result.reject(&:empty?)
      end

      def block(element)
        case element.name
        when *HEADINGS then heading(element)
        when "ul", "ol" then [list(element)]
        when "table" then [caption(element), table(element)]
        when "pre" then [code(element.text)]
        when "blockquote" then [quote(element)]
        when "hr" then []
        else blocks(element)
        end
      end

      # A heading on one line, so that it stays one Markdown heading.
      def heading(element)
        text = squeeze(flat_text(element))
        text.empty? ? [] : ["#{"#" * element.name[1].to_i} #{text}"]
      end

      def list(element)
        items = element.element_children.select { it.name == "li" }
        items.each_with_index.map do |item, index|
          marker = element.name == "ol" ? "#{index + 1}. " : "- "
          lines = blocks(item).join("\n").lines(chomp: true)
          ([marker + lines.first.to_s] + lines.drop(1).map { "#{" " * marker.length}#{it}" }).join("\n")
        end.join("\n")
      end

      # Pipe table: the first row is the header; colspan cells are padded
      # with empty ones and short rows filled up.
      def table(element)
        rows = element.css("tr").select { it.ancestors("table").first == element }.map { cells(it) }
        return "" if rows.empty?

        width = rows.map(&:size).max
        rows = rows.map { it + ([""] * (width - it.size)) }
        lines = rows.map { "| #{it.join(" | ")} |" }
        lines.insert(1, "|#{" --- |" * width}")
        lines.join("\n")
      end

      # The caption of a table, a paragraph before it; "" without one.
      def caption(table)
        caption = table.element_children.find { it.name == "caption" }
        caption ? inline(caption.children) : ""
      end

      def cells(row)
        row.element_children.select { CELLS.include?(it.name) }.flat_map do |cell|
          [cell_text(cell)] + Array.new(cell["colspan"].to_i.clamp(1, nil) - 1, "")
        end
      end

      def cell_text(cell) = squeeze(flat_text(cell)).gsub("|", "\\|")

      # The text of node on one line: inline elements joined as they are,
      # blocks, cells and line breaks set apart by spaces.
      def flat_text(node)
        node.children.map do |child|
          if child.text? then child.text
          elsif skip?(child) || !child.element? then ""
          elsif child.name == "br" then " "
          elsif block?(child) || CELLS.include?(child.name) || child.name == "tr" then " #{flat_text(child)} "
          else flat_text(child)
          end
        end.join
      end

      def code(text)
        longest = text.scan(/`+/).map(&:length).max.to_i
        fence = "`" * [3, longest + 1].max
        "#{fence}\n#{text.chomp}\n#{fence}"
      end

      def quote(element)
        blocks(element).join("\n\n").lines(chomp: true).map { it.empty? ? ">" : "> #{it}" }.join("\n")
      end

      # A run of inline nodes as one paragraph; images alone give their alt.
      def paragraph(run)
        content = run.reject { it.text? && it.text.strip.empty? }
        return content.map { it["alt"].to_s.strip }.reject(&:empty?).join(" ") if image_only?(content)

        inline(run)
      end

      def image_only?(nodes) = !nodes.empty? && nodes.all? { it.element? && it.name == "img" }

      def inline(nodes)
        text = nodes.map { inline_text(it) }.join
        text.split(BREAK).map { squeeze(it) }.join("\n").strip
      end

      def inline_text(node)
        return node.text if node.text?
        return "" unless node.element? && !SKIP.include?(node.name)
        return BREAK if node.name == "br"

        node.children.map { inline_text(it) }.join
      end

      def squeeze(text) = text.gsub(/[[:space:]]+/, " ").strip

      def skip?(node) = node.comment? || (node.element? && SKIP.include?(node.name))

      # A known block element, or another element that holds one.
      def block?(node)
        return false unless node.element?

        BLOCKS.include?(node.name) || node.element_children.any? { block?(it) }
      end

    end
  end
end
