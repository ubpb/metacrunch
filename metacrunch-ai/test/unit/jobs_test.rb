# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

# A job that builds its embedder from params runs in tests with the fake embedder.
class JobsTest < Minitest::Test

  JOB = Metacrunch::Loader.load(File.expand_path("../fixtures/jobs/embed.rb", __dir__))
  BOOKS = (1..9).map { {"title" => "Book #{it}"} }

  def test_runs_with_the_fake_embedder
    result = Metacrunch::Testing.run(JOB, params: {embeddings_url: "fake:4"}, source: BOOKS)

    assert_equal :ok, result.status
    assert(result.records.all? { it["embedding"].size == 4 })
  end

  def test_runs_with_the_fake_embedder_and_workers
    inline = Metacrunch::Testing.run(JOB, params: {embeddings_url: "fake:4"}, source: BOOKS)
    workers = Metacrunch::Testing.run(JOB, params: {embeddings_url: "fake:4"}, source: BOOKS, workers: 2)

    assert_equal inline.records, workers.records
  end

end
