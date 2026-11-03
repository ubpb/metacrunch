# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class ChunkTest < Minitest::Test

  # An embedder that notes the texts it gets.
  class Recorder < Metacrunch::Ai::FakeEmbedder

    attr_reader :texts

    def embed(texts)
      (@texts ||= []).concat(texts)
      super
    end

  end

  LOANS = {"id" => "loans.html", "title" => "Loans", "sha256" => "abc", "text" => "# Loans\n\nFour weeks."}.freeze

  def test_chunk_records
    assert_equal [{"title" => "Loans", "sha256" => "abc", "id" => "loans.html#1", "parent_id" => "loans.html",
                   "chunk" => 1, "headings" => ["Loans"], "text" => "Four weeks."}],
                 run_chunk([LOANS]).records
  end

  def test_numbers_and_ids
    doc = {"id" => "rules", "text" => "One. Two. Three. Four."}
    records = run_chunk([doc], size: 12, overlap: 0).records

    assert_equal([["rules#1", 1], ["rules#2", 2]], records.map { it.values_at("id", "chunk") })
  end

  def test_pages_for_page_arrays
    records = run_chunk([{"id" => "a.pdf", "text" => ["Page one.", "Page two."]}, LOANS]).records

    assert_equal [1, 2], records.first["pages"]
    refute records.last.key?("pages")
  end

  def test_keep_copies_only_those
    record = run_chunk([LOANS], keep: ["title"]).records.first

    assert_equal ["title", "id", "parent_id", "chunk", "headings", "text"], record.keys
  end

  def test_the_chunks_own_fields_win
    record = run_chunk([LOANS.merge("chunk" => "old", "headings" => "old")]).records.first

    assert_equal [1, ["Loans"]], record.values_at("chunk", "headings")
  end

  def test_an_integer_id
    record = run_chunk([LOANS.merge("id" => 17)]).records.first

    assert_equal ["17#1", 17], record.values_at("id", "parent_id")
  end

  def test_other_fields
    doc = {"isbn" => "978-3", "body" => "Four weeks."}
    record = run_chunk([doc], text: "body", into: "passage", id: "isbn").records.first

    assert_equal({"isbn" => "978-3", "id" => "978-3#1", "parent_id" => "978-3", "chunk" => 1, "headings" => [],
                  "passage" => "Four weeks."}, record)
  end

  def test_no_text_is_marked
    result = run_chunk([{"id" => 1}, {"id" => 2, "text" => ""}, {"id" => 3, "text" => ["", nil]}])

    assert_empty result.records
    assert_equal({"No text to chunk" => 3}, result.stats.marked)
  end

  def test_headings_only_is_no_text
    result = run_chunk([{"id" => 1, "text" => "# A\n\n## B"}])

    assert_equal [[], {"No text to chunk" => 1}], [result.records, result.stats.marked]
  end

  def test_a_missing_id_fails
    error = run_chunk([{"text" => "x"}]).failures.first.last.error

    assert_equal [Metacrunch::ContractError, "Chunk needs the id of the document in field id"],
                 [error.class, error.message]
  end

  def test_needs_hash_records
    error = run_chunk(["x"]).failures.first.last.error

    assert_equal "Chunk needs Hash records, got String", error.message
  end

  def test_text_must_be_a_string_or_pages
    error = run_chunk([{"id" => 1, "text" => 42}]).failures.first.last.error

    assert_equal "Chunk needs a String or an Array of pages in field text, got Integer", error.message
  end

  def test_works_with_workers
    docs = (1..6).map { {"id" => it, "text" => "# Part #{it}\n\nOne. Two. Three."} }
    inline = run_chunk(docs, size: 10, overlap: 0).records
    forked = run_chunk(docs, workers: 2, size: 10, overlap: 0).records

    assert_equal inline, forked
    assert_equal 12, forked.size
  end

  def test_with_embed_the_headings_come_first
    recorder = Recorder.new
    chunk = Metacrunch::Ai::Chunk.new
    embed = Metacrunch::Ai::Embed.new(recorder, text: ["title", "headings", "text"])
    job = Metacrunch.job do
      flat_map chunk
      map embed, batch: 10
    end
    Metacrunch::Testing.run(job, source: [LOANS])

    assert_equal ["metacrunch", "Loans\nLoans\nFour weeks."], recorder.texts
  end

  private

  def run_chunk(records, workers: nil, **)
    chunk = Metacrunch::Ai::Chunk.new(**)
    job = Metacrunch.job do
      flat_map chunk
      on_failure :skip
    end
    Metacrunch::Testing.run(job, source: records, workers:)
  end

end
