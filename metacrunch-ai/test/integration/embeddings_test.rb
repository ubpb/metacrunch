# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class EmbeddingsTest < Minitest::Test

  include Integration

  TITLES = ["Introduction to cataloging", "Cataloging for beginners", "Volcanoes of Iceland"].freeze

  def teardown
    @embedder&.close
    super
  end

  def test_embeds_texts
    @embedder = Metacrunch::Ai::OpenAi.new(url:, model:)
    cataloging, beginners, volcanoes = @embedder.embed(TITLES)

    assert_equal [384] * 3, [cataloging, beginners, volcanoes].map(&:size)
    assert_operator cosine(cataloging, beginners), :>, cosine(cataloging, volcanoes)
  end

  def test_embeds_records_in_a_job_inline_and_with_workers
    records = (1..7).map { {"title" => "Book number #{it}"} }
    inline = run_job(records)
    workers = run_job(records, workers: 2)

    assert(inline.all? { it["embedding"].size == 384 })
    assert_equal(inline.map { it["title"] }, workers.map { it["title"] })
    assert_in_delta 0.0, inline.zip(workers).sum { |a, b| distance(a["embedding"], b["embedding"]) }, 1e-6
  end

  def test_an_unknown_model_stops_the_job_when_it_opens
    job = Metacrunch.job do
      params { use Metacrunch::Ai::EMBEDDINGS_PARAMS }
      map Metacrunch::Ai::Embed.new(Metacrunch::Ai.embedder(params), text: "title"), batch: 2
    end
    params = {embeddings_url: url, embeddings_model: "no-such-model"}
    result = Metacrunch::Testing.run(job, params:, source: [{"title" => "a"}])

    assert_equal :aborted, result.status
    assert_kind_of Metacrunch::Ai::ApiError, result.error
  end

  private

  def run_job(records, workers: nil)
    job = Metacrunch.job do
      params { use Metacrunch::Ai::EMBEDDINGS_PARAMS }
      map Metacrunch::Ai::Embed.new(Metacrunch::Ai.embedder(params, max_inputs: 2), text: "title"), batch: 5
    end
    result = Metacrunch::Testing.run(job, params: {embeddings_url: url, embeddings_model: model}, source: records,
                                          workers:)
    raise result.error if result.error

    result.records
  end

  def cosine(one, two) = one.zip(two).sum { |x, y| x * y } / Math.sqrt(one.sum { it * it } * two.sum { it * it })

  def distance(one, two) = Math.sqrt(one.zip(two).sum { |x, y| (x - y)**2 })

end
