# frozen_string_literal: true

require "test_helper"

class OpenAiTest < Minitest::Test

  def setup
    @api = FakeApi.new
  end

  def teardown
    @embedder&.close
    @api.stop
  end

  def test_posts_model_and_input_to_embeddings
    answer_with([[0.1, 0.2], [0.3, 0.4]])

    assert_equal [[0.1, 0.2], [0.3, 0.4]], embedder.embed(["a", "b"])
    assert_equal ["/v1/embeddings", {"model" => "m", "input" => ["a", "b"]}],
                 [@api.requests.first.path, @api.requests.first.json]
  end

  def test_sends_the_key_as_bearer_and_extra_headers_and_body
    answer_with([[1.0]])
    embedder(api_key: "secret", headers: {"api-key" => "x"}, body: {dimensions: 256}).embed(["a"])
    request = @api.requests.first

    assert_equal ["Bearer secret", "x"], request.headers.values_at("authorization", "api-key")
    assert_equal({"dimensions" => 256, "model" => "m", "input" => ["a"]}, request.json)
  end

  def test_model_and_input_win_over_the_body
    answer_with([[1.0]])
    embedder(body: {"model" => "other", "input" => ["x"], "dimensions" => 8}).embed(["a"])

    assert_equal({"model" => "m", "input" => ["a"], "dimensions" => 8}, @api.requests.first.json)
  end

  def test_no_authorization_without_a_key
    answer_with([[1.0]])
    embedder.embed(["a"])

    refute @api.requests.first.headers.key?("authorization")
  end

  def test_orders_vectors_by_index
    @api.on("POST", "/v1/embeddings") do
      [200, {"data" => [{"index" => 1, "embedding" => [2.0]}, {"index" => 0, "embedding" => [1]}]}]
    end

    assert_equal [[1.0], [2.0]], embedder.embed(["a", "b"])
  end

  def test_takes_the_order_of_the_answer_without_index
    @api.on("POST", "/v1/embeddings") { [200, {"data" => [{"embedding" => [1.0]}, {"embedding" => [2]}]}] }

    assert_equal [[1.0], [2.0]], embedder.embed(["a", "b"])
  end

  def test_sums_usage_into_stats
    @api.on("POST", "/v1/embeddings") { [200, answer([[1.0]], usage: {"prompt_tokens" => 4, "total_tokens" => 4})] }
    @api.on("POST", "/v1/embeddings", times: 1) { [200, answer([[1.0]], usage: {"total_tokens" => 3})] }
    openai = embedder
    2.times { openai.embed(["a"]) }

    assert_equal({"requests" => 2, "tokens" => 7}, openai.stats)
  end

  def test_stats_without_usage_have_no_tokens
    answer_with([[1.0]])
    embedder.embed(["a"])

    assert_equal({"requests" => 1}, @embedder.stats)
  end

  def test_a_malformed_answer_is_an_api_error
    [
      {"data" => [{"index" => 0, "embedding" => [1.0]}]},
      {"data" => [{"index" => 0, "embedding" => ["x"]}, {"index" => 1, "embedding" => [1.0]}]},
      {"data" => [{"index" => 0, "embedding" => [1.0]}, {"index" => 0, "embedding" => [1.0]}]},
      {"data" => [1, {"index" => 1, "embedding" => [1.0]}]},
      {"data" => [1, {"embedding" => [1.0]}]},
      {"data" => [{"index" => 0, "embedding" => [1.0]}, {"embedding" => [1.0]}]},
      {"vectors" => []}
    ].each do |body|
      @api.on("POST", "/v1/embeddings", times: 1) { [200, body] }

      assert_raises(Metacrunch::Ai::ApiError, body.inspect) { embedder.embed(["a", "b"]) }
    end
  end

  def test_names_the_count_in_a_malformed_answer
    answer_with([[1.0]])
    error = assert_raises(Metacrunch::Ai::ApiError) { embedder.embed(["a", "b"]) }

    assert_equal "embeddings at #{@api.url("/v1/embeddings")}: malformed answer, 1 vector for 2 texts", error.message
  end

  def test_names_more_vectors_than_texts
    answer_with([[1.0], [2.0]])
    error = assert_raises(Metacrunch::Ai::ApiError) { embedder.embed(["a"]) }

    assert_match(/malformed answer, 2 vectors for 1 text\z/, error.message)
  end

  def test_ignores_usage_without_a_count_of_tokens
    @api.on("POST", "/v1/embeddings") { [200, answer([[1.0]], usage: {"prompt_tokens" => "many"})] }
    openai = embedder
    openai.embed(["a"])

    assert_equal({"requests" => 1}, openai.stats)
  end

  def test_refuses_more_than_max_inputs
    error = assert_raises(ArgumentError) { embedder(max_inputs: 2).embed(["a", "b", "c"]) }

    assert_equal "at most 2 texts per call (max_inputs), got 3", error.message
  end

  def test_defaults
    openai = Metacrunch::Ai::OpenAi.new(model: "m")

    assert_equal ["https://api.openai.com/v1", 32, "m"], [openai.url, openai.max_inputs, openai.model]
  end

  def test_validates_options
    [{model: nil}, {model: ""}, {max_inputs: 0}, {url: "ftp://x"}, {headers: []}, {body: "x"}, {api_key: 1},
     {timeout: 0}, {retries: -1}].each do |options|
      assert_raises(ArgumentError, options.inspect) { Metacrunch::Ai::OpenAi.new(model: "m", **options) }
    end
  end

  def test_inspect_hides_the_key
    text = Metacrunch::Ai::OpenAi.new(model: "m", api_key: "secret").inspect

    assert_equal %(#<Metacrunch::Ai::OpenAi model="m" url="https://api.openai.com/v1">), text
  end

  def test_open_takes_the_logger_of_the_context
    log = StringIO.new
    @api.on("POST", "/v1/embeddings") { [200, answer([[1.0]])] }
    @api.on("POST", "/v1/embeddings", times: 1) { [503, {}, {"Retry-After" => "0"}] }
    @embedder = Metacrunch::Ai::OpenAi.new(model: "m", url: @api.url("/v1"))
    @embedder.open(Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log)))
    @embedder.embed(["a"])

    assert_includes log.string, "embeddings: 503, retry 1/5 in 0.0 s"
  end

  private

  def embedder(**)
    @embedder = Metacrunch::Ai::OpenAi.new(model: "m", url: @api.url("/v1"), **).tap(&:open)
  end

  def answer(vectors, usage: nil)
    {"data" => vectors.each_with_index.map { |vector, index| {"index" => index, "embedding" => vector} },
     "usage" => usage}.compact
  end

  def answer_with(vectors)
    @api.on("POST", "/v1/embeddings") { [200, answer(vectors)] }
  end

end
