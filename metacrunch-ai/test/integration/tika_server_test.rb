# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

# The Tika extractor against a Tika server, with the files in test/fixtures/documents.
class TikaServerTest < Minitest::Test

  include TikaServer

  FIXTURES = File.expand_path("../fixtures/documents", __dir__)
  DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  def teardown
    @tika&.close
  end

  def test_a_pdf_gives_its_pages_and_title
    result = tika.extract(read("loans.pdf"), type: "application/pdf")

    assert_equal 2, result[:text].size
    assert(result[:text].all? { it.match?(/loan/i) }, "every page names loans")
    assert_equal "Loans and renewals", result[:title]
  end

  def test_a_docx_keeps_its_headings
    text = tika.extract(read("handbook.docx"), type: DOCX)[:text]

    assert_match(/^# Borrowing$/, text)
    assert_match(/^## Renewals$/, text)
  end

  def test_an_encrypted_pdf_is_invalid_input
    error = assert_raises(Metacrunch::Ai::InvalidInput) { tika.extract(read("encrypted.pdf"), type: "application/pdf") }

    assert_equal "document is encrypted", error.message
  end

  def test_a_truncated_pdf_is_invalid_input
    assert_raises(Metacrunch::Ai::InvalidInput) { tika.extract(read("truncated.pdf"), type: "application/pdf") }
  end

  def test_files_are_extracted_and_chunked
    reader = Metacrunch::FileList::Reader.new(FIXTURES)
    extract = Metacrunch::Ai::Extract.new(Metacrunch::Ai::Html.new, Metacrunch::Ai::Text.new,
                                          Metacrunch::Ai::Tika.new(url: tika_url))
    chunk = Metacrunch::Ai::Chunk.new(size: 200, overlap: 0)
    job = Metacrunch.job do
      source reader, id: ->(file) { file["id"] }
      map extract
      flat_map chunk
      on_failure :skip
    end
    result = Metacrunch::Testing.run(job)
    pdf = result.records.select { it["parent_id"] == "loans.pdf" }

    assert_equal [1, 2], pdf.flat_map { it["pages"] }.uniq.sort
    assert_equal(["encrypted.pdf", "truncated.pdf"], result.failures.map { it.first["id"] }.sort)
  end

  private

  def tika = (@tika = Metacrunch::Ai::Tika.new(url: tika_url).open)

  def read(name) = File.binread(File.join(FIXTURES, name))

end
