# frozen_string_literal: true

module Metacrunch
  module Ai
    # Cuts text into chunks by its structure, recursively, as comparable
    # tools do: Markdown headings start sections, which know their heading
    # path; a section's body is split at blank lines, then lines, sentence
    # ends and spaces, and cut hard only where nothing else helps, until
    # every piece fits size; the pieces are joined again into chunks of at
    # most size, the next one starting with whole pieces of the last, up to
    # overlap. Code blocks and tables are split only when they do not fit.
    # Small consecutive sections share a chunk, with the heading lines of
    # the later ones in its text. Pages (an Array of Strings) are numbered
    # from 1; a chunk knows the pages its text comes from.
    #
    # size and overlap are measured by length:, a callable that gives the
    # length of a String (e.g. its tokens), by default its characters.
    class Chunk

      NO_TEXT = "No text to chunk"

      # A chunk: its text, the headings of its path (outermost first), the
      # pages it comes from (nil for text without pages).
      Piece = Data.define(:text, :headings, :pages)

      HEADING = /\A {0,3}(\#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*\z/
      FENCE = /\A {0,3}(`{3,}|~{3,})/
      # The separators inside a block, coarsest first; captured, so the
      # whitespace between pieces is kept.
      SEPARATORS = [/(\n)/, /(?<=[.!?…])(\s+)/, /(\s+)/].freeze
      BLOCK = "\n\n"

      Block = Data.define(:text, :page, :level, :title)
      Section = Struct.new(:path, :line, :page, :blocks)
      Atom = Data.define(:text, :separator, :page, :length)
      Group = Struct.new(:path, :text, :pages)
      private_constant :Block, :Section, :Atom, :Group

      # text: the field with the document's text (a String, or an Array of
      # pages); into: the field of a chunk's text; id: the field with the
      # document's id; keep: the document's fields to copy into its chunks
      # (nil: all but text); headings: false for plain text, whose lines may
      # start with "#".
      def initialize(text: "text", into: "text", id: "id", size: 1000, overlap: 150, length: nil, headings: true,
                     keep: nil)
        @size = Ai.positive!(size, "size")
        unless overlap.is_a?(Integer) && overlap >= 0 && overlap < size
          raise ArgumentError, "overlap must be an Integer from 0 to below size (#{size}), got #{overlap.inspect}"
        end
        unless length.nil? || length.respond_to?(:call)
          raise ArgumentError, "length must be callable, got #{length.inspect}"
        end
        unless [true, false].include?(headings)
          raise ArgumentError, "headings must be true or false, got #{headings.inspect}"
        end

        {text:, into:, id:}.each do |name, value|
          raise ArgumentError, "#{name} must be a non-empty String, got #{value.inspect}" unless Ai.text?(value)
        end
        unless keep.nil? || (keep.is_a?(Array) && keep.all? { Ai.text?(it) })
          raise ArgumentError, "keep must be an Array of field names, got #{keep.inspect}"
        end

        @overlap = overlap
        @length = length
        @headings = headings
        @text = text
        @into = into
        @id = id
        @keep = keep
      end

      # The chunk records of a document, for flat_map: "id" ("#{parent_id}#n",
      # n from 1), "parent_id", "chunk" (n), "headings", "pages" (for pages
      # only) and the text in into:, over the document's fields (all but its
      # text, or those of keep:). A document without text gives none and
      # gets the mark "No text to chunk".
      def call(record, ctx)
        raise ContractError, "Chunk needs Hash records, got #{record.class}" unless record.is_a?(Hash)

        parent = record[@id]
        raise ContractError, "Chunk needs the id of the document in field #{@id}" if parent.nil? || parent == ""

        text = record[@text]
        unless text.nil? || text.is_a?(String) || text.is_a?(Array)
          raise ContractError, "Chunk needs a String or an Array of pages in field #{@text}, got #{text.class}"
        end

        pieces = split(text)
        ctx.mark(NO_TEXT) if pieces.empty?
        fields = @keep ? record.slice(*@keep) : record.except(@text)
        pieces.each_with_index.map { |piece, index| fields.merge(chunk_fields(parent, index + 1, piece)) }
      end

      # The chunks of a String or an Array of pages (nil counts as blank).
      def split(input)
        pages = input.is_a?(Array) ? input.map(&:to_s) : [input.to_s]
        blocks = pages.each_with_index.flat_map do |page, index|
          page_blocks(page.gsub(/\r\n?/, "\n").split("\n").map(&:rstrip), input.is_a?(Array) ? index + 1 : nil)
        end
        merge(sections(blocks))
      end

      private

      def chunk_fields(parent, number, piece)
        fields = {"id" => "#{parent}##{number}", "parent_id" => parent, "chunk" => number, "headings" => piece.headings}
        fields["pages"] = piece.pages if piece.pages
        fields.merge(@into => piece.text)
      end

      # Paragraphs, fenced code blocks, tables and headings of one page; a
      # page's end ends a block.
      def page_blocks(lines, page)
        blocks = []
        paragraph = []
        index = 0
        while index < lines.size
          line = lines[index]
          heading = HEADING.match(line) if @headings
          if line.empty? || heading || line.match?(FENCE) || table?(line)
            blocks << Block.new(text: paragraph.join("\n"), page:, level: nil, title: nil) unless paragraph.empty?
            paragraph = []
          end
          if heading
            blocks << Block.new(text: line.strip, page:, level: heading[1].size, title: heading[2].strip)
          elsif line.match?(FENCE) || table?(line)
            last = line.match?(FENCE) ? fence_end(lines, index) : table_end(lines, index)
            blocks << Block.new(text: lines[index..last].join("\n"), page:, level: nil, title: nil)
            index = last
          elsif !line.empty?
            paragraph << line
          end
          index += 1
        end
        blocks << Block.new(text: paragraph.join("\n"), page:, level: nil, title: nil) unless paragraph.empty?
        blocks
      end

      def table?(line) = line.lstrip.start_with?("|")

      # The index of the line that closes the fence opened at index, or of
      # the page's last line.
      def fence_end(lines, index)
        fence = lines[index][FENCE, 1]
        closing = /\A {0,3}#{Regexp.escape(fence[0])}{#{fence.size},}[ \t]*\z/
        ((index + 1)...lines.size).find { lines[it].match?(closing) } || (lines.size - 1)
      end

      def table_end(lines, index)
        index += 1 while index + 1 < lines.size && table?(lines[index + 1])
        index
      end

      # Sections with their heading paths. A heading without body and without
      # subsections is no section: its line stays text, under its parent's
      # path, so that it is not lost.
      def sections(blocks)
        stack = []
        sections = [Section.new([], nil, nil, [])]
        blocks.each_with_index do |block, index|
          next sections.last.blocks << block unless block.level

          stack.pop while stack.any? && stack.last.first >= block.level
          following = blocks[index + 1]
          if following.nil? || (following.level && following.level <= block.level)
            sections << Section.new(stack.map(&:last), nil, block.page, [block.with(level: nil, title: nil)])
          else
            stack << [block.level, block.title]
            sections << Section.new(stack.map(&:last), block.text, block.page, [])
          end
        end
        sections
      end

      # The chunks of every section, with small consecutive ones merged; a
      # section without body (whose heading is in the next path) adds only
      # its heading line to a merged chunk.
      def merge(sections)
        pieces = []
        group = nil
        pending = []
        sections.each do |section|
          chunks = pack(atoms(section))
          if chunks.empty?
            pending << section if group
            next
          end
          if group && chunks.one?
            text = [group.text, *pending.map(&:line), section.line, join(chunks.first)].compact.join(BLOCK)
            if measure(text) <= @size
              group.text = text
              group.pages.concat(pending.map(&:page), [section.page], chunks.first.map(&:page))
              pending = []
              next
            end
          end

          pieces << piece(group.path, group.text, group.pages) if group
          group = nil
          pending = []
          if chunks.one?
            group = Group.new(section.path, join(chunks.first), chunks.first.map(&:page))
          else
            chunks.each { pieces << piece(section.path, join(it), it.map(&:page)) }
          end
        end
        pieces << piece(group.path, group.text, group.pages) if group
        pieces
      end

      def piece(path, text, pages)
        pages = pages.compact.uniq.sort
        Piece.new(text:, headings: path, pages: pages.empty? ? nil : pages)
      end

      # The pieces of a section's body, each fitting size, with the
      # separator before each.
      def atoms(section)
        section.blocks.each_with_object([]) do |block, atoms|
          fit(block.text).each_with_index do |(text, separator, length), index|
            separator = atoms.empty? ? "" : BLOCK if index.zero?
            atoms << Atom.new(text:, separator:, page: block.page, length:)
          end
        end
      end

      # [text, separator before it, length] for the pieces of text at the
      # coarsest separator level that makes them fit.
      def fit(text, level = 0)
        length = measure(text)
        return [[text, nil, length]] if length <= @size
        return cut(text) if level == SEPARATORS.size

        parts = text.split(SEPARATORS[level])
        return fit(text, level + 1) if parts.one?

        result = []
        separator = nil
        parts.each_slice(2) do |part, after|
          unless part.empty?
            pieces = fit(part, level + 1)
            pieces.first[1] = separator
            result.concat(pieces)
            separator = nil
          end
          separator = "#{separator}#{after}" if after
        end
        result
      end

      # Hard cuts at the longest prefixes that fit.
      def cut(text)
        pieces = []
        offset = 0
        while offset < text.length
          count = prefix(text, offset)
          piece = text[offset, count]
          pieces << [piece, pieces.empty? ? nil : "", measure(piece)]
          offset += count
        end
        pieces
      end

      # The length in characters of the longest prefix of text from offset
      # that fits size, at least 1: by galloping and bisection with length:.
      def prefix(text, offset)
        rest = text.length - offset
        return [@size, rest].min unless @length

        fits = ->(count) { measure(text[offset, count]) <= @size }
        low = 0
        high = [@size, rest].min
        while fits.call(high)
          return high if high == rest

          low = high
          high = [high * 2, rest].min
        end
        while high - low > 1
          middle = (low + high) / 2
          fits.call(middle) ? low = middle : high = middle
        end
        [low, 1].max
      end

      # Joins atoms greedily into chunks of at most size; a chunk after the
      # first of a section starts with the overlap of the one before.
      def pack(atoms)
        chunks = []
        current = []
        total = 0
        atoms.each do |atom|
          if current.any? && !fits?(current, total, atom)
            chunks << current
            current = tail(current)
            current = current.drop(1) while current.any? && !fits?(current, joined_length(current), atom)
            total = joined_length(current)
          end
          total += current.empty? ? atom.length : measure(atom.separator) + atom.length
          current += [atom]
        end
        chunks << current if current.any?
        chunks
      end

      def fits?(current, total, atom)
        return measure(join(current + [atom])) <= @size if @length

        total + atom.separator.length + atom.length <= @size
      end

      # The last atoms of chunk whose joined length is at most overlap.
      def tail(chunk)
        kept = []
        chunk.reverse_each do |atom|
          candidate = [atom, *kept]
          break if joined_length(candidate) > @overlap

          kept = candidate
        end
        kept
      end

      def joined_length(atoms)
        return measure(join(atoms)) if @length

        atoms.sum(&:length) + atoms.drop(1).sum { it.separator.length }
      end

      def join(atoms)
        return "" if atoms.empty?

        [atoms.first.text, *atoms.drop(1).map { it.separator + it.text }].join
      end

      def measure(text) = @length ? @length.call(text) : text.length

    end
  end
end
