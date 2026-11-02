# frozen_string_literal: true

require "test_helper"

class EmbedderTest < Minitest::Test

  def test_embeddings_params_declare_url_model_and_a_secret_key
    definitions = Metacrunch::Params.new.tap { it.use(Metacrunch::Ai::EMBEDDINGS_PARAMS) }.definitions

    assert_equal [:embeddings_url, :embeddings_model, :embeddings_api_key], definitions.keys
    assert_equal [false, false, true], definitions.values.map(&:secret?)
    assert(definitions.values.all? { Metacrunch::Ai.text?(it.desc) })
  end

  def test_builds_an_openai_embedder_from_params
    params = bound(embeddings_url: "http://localhost:11435/v1", embeddings_model: "all-minilm",
                   embeddings_api_key: "secret")
    embedder = Metacrunch::Ai.embedder(params, max_inputs: 64)

    assert_instance_of Metacrunch::Ai::OpenAi, embedder
    assert_equal ["http://localhost:11435/v1", "all-minilm", 64], [embedder.url, embedder.model, embedder.max_inputs]
  end

  def test_the_url_defaults_to_openai
    embedder = Metacrunch::Ai.embedder(bound(embeddings_model: "text-embedding-3-small"))

    assert_equal Metacrunch::Ai::OpenAi::DEFAULT_URL, embedder.url
  end

  def test_fake_gives_a_fake_embedder
    fakes = ["fake", "fake:384"].map { Metacrunch::Ai.embedder(bound(embeddings_url: it)) }

    assert(fakes.all?(Metacrunch::Ai::FakeEmbedder))
    assert_equal [8, 384], fakes.map(&:dims)
  end

  def test_the_fake_takes_max_inputs_only
    fake = Metacrunch::Ai.embedder(bound(embeddings_url: "fake"), max_inputs: 4, headers: {"x" => "y"})

    assert_equal 4, fake.max_inputs
  end

  def test_a_bad_fake_is_refused
    ["fake:x", "fake:0", "fake:"].each do |url|
      assert_raises(ArgumentError, url) { Metacrunch::Ai.embedder(bound(embeddings_url: url)) }
    end
  end

  def test_the_model_is_required_without_a_fake
    error = assert_raises(ArgumentError) { Metacrunch::Ai.embedder(bound({})) }

    assert_equal "embeddings_model is required (or embeddings_url fake for a fake embedder)", error.message
  end

  def test_reads_only_the_params_the_job_declares
    params = Metacrunch::Params.new.tap { it.param(:embeddings_model, String) }.bind_values({embeddings_model: "m"})

    assert_equal "m", Metacrunch::Ai.embedder(params).model
  end

  private

  def bound(values)
    Metacrunch::Params.new.tap { it.use(Metacrunch::Ai::EMBEDDINGS_PARAMS) }.bind_values(values)
  end

end
