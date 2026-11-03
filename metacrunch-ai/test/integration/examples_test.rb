# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

# Runs the example as a user would, through metacrunch's executable: with the fake embedder always, against the
# embeddings server when EMBEDDINGS_URL is set.
class ExamplesTest < Minitest::Test

  EXAMPLES = File.expand_path("../../examples", __dir__)

  def test_the_example_runs_with_the_fake_embedder
    books = run!("--embeddings-url", "fake:384")

    assert_equal 7, books.size
    assert_equal([384] * 6, books.filter_map { it["embedding"]&.size })
  end

  def test_the_example_runs_against_the_server
    skip Integration::HINT unless ENV["EMBEDDINGS_URL"]

    books = run!("--embeddings-url", ENV.fetch("EMBEDDINGS_URL"),
                 "--embeddings-model", ENV.fetch("EMBEDDINGS_MODEL", "all-minilm"))

    assert_equal([384] * 6, books.filter_map { it["embedding"]&.size })
  end

  def test_the_documents_example_runs_with_the_fake_embedder
    skip TikaServer::HINT unless ENV["TIKA_URL"]

    check_chunks(run_documents!("--embeddings-url", "fake:384"))
  end

  def test_the_documents_example_runs_against_the_servers
    skip TikaServer::HINT unless ENV["TIKA_URL"]
    skip Integration::HINT unless ENV["EMBEDDINGS_URL"]

    check_chunks(run_documents!("--embeddings-url", ENV.fetch("EMBEDDINGS_URL"),
                                "--embeddings-model", ENV.fetch("EMBEDDINGS_MODEL", "all-minilm")))
  end

  private

  def check_chunks(chunks)
    documents = chunks.map { it["parent_id"] }.uniq.sort
    loans = chunks.select { it["parent_id"] == "loans.html" }.map { it["text"] }.join

    assert_equal ["loans.html", "opening-hours.html", "reading-room.md", "rules.pdf", "services.docx"], documents
    assert(chunks.all? { it["chunk"].is_a?(Integer) && it["embedding"]&.size == 384 })
    assert_equal [1, 2], chunks.select { it["parent_id"] == "rules.pdf" }.flat_map { it["pages"] }.uniq.sort
    refute_match(/Menu|Imprint/, loans)
    assert_equal([["Reading room", "https://www.example.org/reading-room"]],
                 chunks.select { it["parent_id"] == "reading-room.md" }.map { it.values_at("title", "source") }.uniq)
  end

  def run_documents!(*)
    Dir.mktmpdir do |dir|
      output = File.join(dir, "chunks.jsonl")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, Integration::BIN, "run", "documents.rb", *,
                                               "--tika-url", ENV.fetch("TIKA_URL"), "--output", output,
                                               "data/documents", chdir: EXAMPLES)

      assert_predicate status, :success?, stderr
      File.readlines(output).map { JSON.parse(it) }
    end
  end

  def run!(*)
    Dir.mktmpdir do |dir|
      output = File.join(dir, "books.jsonl")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, Integration::BIN, "run", "embed.rb", *, "--output",
                                               output, "data/books.jsonl", chdir: EXAMPLES)

      assert_predicate status, :success?, stderr
      assert_match(/embedded 6 texts in 1 call\b/, stderr)
      File.readlines(output).map { JSON.parse(it) }
    end
  end

end
