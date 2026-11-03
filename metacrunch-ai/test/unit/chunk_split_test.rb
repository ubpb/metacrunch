# frozen_string_literal: true

require "test_helper"

class ChunkSplitTest < Minitest::Test

  Piece = Metacrunch::Ai::Chunk::Piece
  DOC = "# A\n\nx\n\n## B\n\ny\n\n# C\n\nz"
  HEADING = /\A {0,3}\#{1,6}[ \t]+\S/

  def test_a_short_text_is_one_piece
    assert_equal [Piece.new(text: "Loans run four weeks.", headings: [], pages: nil)],
                 chunk.split("Loans run four weeks.")
  end

  def test_heading_paths
    pieces = chunk(size: 5, overlap: 0).split(DOC)

    assert_equal [["A"], ["A", "B"], ["C"]], pieces.map(&:headings)
    assert_equal ["x", "y", "z"], pieces.map(&:text)
  end

  def test_small_sections_are_merged
    pieces = chunk(size: 100, overlap: 0).split(DOC)

    assert_equal([[["A"], "x\n\n## B\n\ny\n\n# C\n\nz"]], pieces.map { [it.headings, it.text] })
  end

  def test_sections_without_body_give_no_piece
    assert_equal([[["A", "B"], "x"]], chunk.split("# A\n\n## B\n\nx").map { [it.headings, it.text] })
  end

  def test_empty_sections_between_merged_ones_keep_their_heading_lines
    pieces = chunk(size: 100, overlap: 0).split("# A\n\nx\n\n# B\n\n## C\n\ny")

    assert_equal([[["A"], "x\n\n# B\n\n## C\n\ny"]], pieces.map { [it.headings, it.text] })
  end

  def test_a_heading_without_body_or_subsections_stays_in_the_text
    pieces = chunk(size: 5, overlap: 0).split("# A\n\nx\n\n# B\n\n# C\n\ny")

    assert_equal([[["A"], "x"], [[], "# B"], [["C"], "y"]], pieces.map { [it.headings, it.text] })
  end

  def test_a_first_heading_without_body_stays_in_the_text
    pieces = chunk(size: 100, overlap: 0).split("# A\n\n# B\n\nx")

    assert_equal([[[], "# A\n\n# B\n\nx"]], pieces.map { [it.headings, it.text] })
  end

  def test_headings_only_give_their_text
    assert_equal([[["Only"], "## Headings"]], chunk.split("# Only\n\n## Headings").map { [it.headings, it.text] })
  end

  def test_headings_with_closing_hashes_and_indent
    assert_equal [["Loans", "Renewals"]], chunk.split("# Loans #\n\n  ## Renewals ##\n\nx").map(&:headings)
  end

  def test_headings_inside_code_fences_are_text
    pieces = chunk(size: 100, overlap: 0).split("# A\n\n```\n# not a heading\n```\n\nx")

    assert_equal([[["A"], "```\n# not a heading\n```\n\nx"]], pieces.map { [it.headings, it.text] })
  end

  def test_headings_off
    assert_equal([[[], "# A\n\nx"]], chunk(headings: false).split("# A\n\nx").map { [it.headings, it.text] })
  end

  def test_paragraphs_then_lines_then_sentences_then_spaces
    small = chunk(size: 5, overlap: 0)
    texts = ["aaaa\n\nbbbb", "aaaa\nbbbb", "Aaa. Bbb.", "aaaa bbbb"].map { texts(small, it) }

    assert_equal [["aaaa", "bbbb"], ["aaaa", "bbbb"], ["Aaa.", "Bbb."], ["aaaa", "bbbb"]], texts
  end

  def test_a_paragraph_that_fits_stays_whole
    assert_equal ["aa bb", "cc dd"], texts(chunk(size: 6, overlap: 0), "aa bb\n\ncc dd")
  end

  def test_a_long_word_is_cut_hard
    assert_equal ["a" * 10, "a" * 10, "a" * 5], texts(chunk(size: 10, overlap: 0), "a" * 25)
  end

  def test_code_blocks_and_tables_stay_whole
    code = "```\nline one\nline two\n```"
    table = "| a | b |\n| c | d |"

    assert_equal ["Intro.", code, table], texts(chunk(size: 25, overlap: 0), "Intro.\n\n#{code}\n\n#{table}")
  end

  def test_too_long_code_is_split_at_lines
    assert_equal ["```\nline one", "line two\n```"],
                 texts(chunk(size: 15, overlap: 0), "```\nline one\nline two\n```")
  end

  def test_overlap_of_whole_sentences
    assert_equal ["One. Two.", "Two. Three.", "Three. Four."],
                 texts(chunk(size: 15, overlap: 6), "One. Two. Three. Four.")
  end

  def test_no_overlap_across_sections
    pieces = chunk(size: 12, overlap: 6).split("# A\n\nOne. Two. Three.\n\n# B\n\nFour.")

    assert_equal [["A"], ["A"], ["B"]], pieces.map(&:headings)
    assert_equal ["One. Two.", "Two. Three.", "Four."], pieces.map(&:text)
  end

  def test_overlap_dropped_when_too_long
    assert_equal ["Aaaa.", "Bbbbbbbbb."], texts(chunk(size: 10, overlap: 5), "Aaaa. Bbbbbbbbb.")
  end

  def test_pages_of_merged_text
    pieces = chunk(size: 100, overlap: 0).split(["Page one.", "", nil, "Page four."])

    assert_equal([["Page one.\n\nPage four.", [1, 4]]], pieces.map { [it.text, it.pages] })
  end

  def test_a_chunk_spans_a_page_boundary
    pieces = chunk(size: 15, overlap: 0).split(["First. Second.", "Third."])

    assert_equal([["First. Second.", [1]], ["Third.", [2]]], pieces.map { [it.text, it.pages] })
    assert_equal [[1, 2]], chunk.split(["First.", "Second."]).map(&:pages)
  end

  def test_a_page_end_ends_a_paragraph
    assert_equal ["Loans run\n\nfour weeks."], texts(chunk, ["Loans run", "four weeks."])
  end

  def test_length_counts_words
    words = chunk(size: 3, overlap: 0, length: ->(text) { text.split.size })

    assert_equal ["one two three", "four five"], texts(words, "one two three four five")
  end

  def test_a_long_word_is_cut_by_the_length_function
    pairs = chunk(size: 2, overlap: 0, length: ->(text) { (text.length + 1) / 2 })

    assert_equal ["abcd", "efgh", "i"], texts(pairs, "abcdefghi")
  end

  def test_normalization
    assert_equal ["a\nb\n\nc"], texts(chunk, "a  \r\nb\r\n\r\n\r\n\r\nc")
  end

  def test_nothing_gives_no_piece
    inputs = ["", " \n\n ", [nil, ""]]

    assert_equal([[]] * 3, inputs.map { chunk.split(it) })
  end

  def test_validates_options
    [{size: 0}, {size: 1.5}, {overlap: -1}, {size: 10, overlap: 10}, {overlap: 1.0}, {length: 1}, {text: ""},
     {into: nil}, {id: :id}, {keep: "title"}, {keep: [""]}, {headings: nil}].each do |options|
      assert_raises(ArgumentError, options.inspect) { chunk(**options) }
    end
  end

  def test_guarantees_on_generated_documents
    random = Random.new(20_261_103)
    200.times do
      doc = generated_markdown(random)
      size = [20, 50, 200, 1000].sample(random:)
      body = squeeze(without_heading_lines(doc))
      [0, size / 5].each do |overlap|
        pieces = chunk(size:, overlap:).split(doc)
        message = "in #{doc.inspect}"

        assert(pieces.all? { it.text.length <= size && !it.text.strip.empty? && !own_heading_line?(it) }, message)
        assert_empty lost_headings(doc, pieces), message
        if overlap.zero?
          assert_equal body, squeeze(without_heading_lines(pieces.map(&:text).join("\n"))), message
        else
          assert(pieces.all? { body.include?(squeeze(without_heading_lines(it.text))) }, message)
        end
      end
    end
  end

  def test_ten_megabytes_chunk_in_seconds
    text = "#{(["Loans run four weeks. Renewals are possible online."] * 20).join(" ")}\n\n" * 10_000
    pieces = nil

    assert_operator seconds { pieces = chunk.split(text) }, :<, 10
    assert(pieces.all? { it.text.length <= 1000 })
  end

  def test_a_megabyte_without_whitespace_is_cut_quickly
    pieces = nil

    assert_operator seconds { pieces = chunk.split("x" * 1_000_000) }, :<, 5
    assert_equal([1000] * 1000, pieces.map { it.text.length })
  end

  private

  def chunk(**) = Metacrunch::Ai::Chunk.new(**)

  def texts(chunk, text) = chunk.split(text).map(&:text)

  def seconds
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end

  def squeeze(text) = text.gsub(/\s+/, "")

  # Removes ATX heading lines outside fenced code.
  def without_heading_lines(text)
    fenced = false
    text.lines.reject do |line|
      fenced = !fenced if line.start_with?("```")
      !fenced && line.match?(HEADING)
    end.join
  end

  # The titles of heading lines (outside fenced code) that are neither in a heading path nor in a text.
  def lost_headings(doc, pieces)
    fenced = false
    titles = doc.lines.filter_map do |line|
      fenced = !fenced if line.start_with?("```")
      line.sub(/\A\s*#+\s*/, "").strip if !fenced && line.match?(HEADING)
    end
    paths = pieces.flat_map(&:headings)
    texts = squeeze(pieces.map(&:text).join("\n"))
    titles.reject { paths.include?(it) || texts.include?(squeeze(it)) }
  end

  def own_heading_line?(piece)
    first = piece.text.lines.first.to_s
    first.match?(HEADING) && piece.headings.include?(first.sub(/\A\s*#+\s*/, "").strip)
  end

  def generated_markdown(random)
    blocks = Array.new(random.rand(1..12)) do
      case random.rand(6)
      # Headings shorter than the smallest size, so the comparison above can strip their lines.
      when 0 then "#{"#" * random.rand(1..4)} #{Array.new(random.rand(1..2)) { word(random, 1..6) }.join(" ")}"
      when 1 then Array.new(random.rand(1..3)) { "- #{words(random, 1..6)}" }.join("\n")
      when 2 then Array.new(random.rand(1..3)) { "| #{words(random, 1..2)} | #{words(random, 1..2)} |" }.join("\n")
      when 3 then "```\n#{Array.new(random.rand(1..3)) { words(random, 1..5) }.join("\n")}\n```"
      else Array.new(random.rand(1..5)) { "#{words(random, 1..12).capitalize}." }.join(" ")
      end
    end
    blocks.join("\n\n")
  end

  def words(random, count)
    Array.new(random.rand(count)) { word(random, random.rand(10).zero? ? 20..60 : 1..9) }.join(" ")
  end

  def word(random, length) = Array.new(random.rand(length)) { ("a".."z").to_a.sample(random:) }.join

end
