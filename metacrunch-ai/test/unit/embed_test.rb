# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class EmbedTest < Minitest::Test

  Fake = Metacrunch::Ai::FakeEmbedder

  # A provider that notes the texts of each call and can fail; with open, close and stats.
  class Recorder < Fake

    attr_reader :calls, :events

    def initialize(fail_with: nil, stats: nil, **)
      super(**)
      @fail_with = fail_with
      @extra_stats = stats
      @calls = []
      @events = []
    end

    def open(context) = @events << [:open, context.class]

    def close = @events << :close

    def embed(texts)
      @calls << texts
      error = @fail_with&.call(texts)
      raise error if error

      super
    end

    def stats = super.merge(@extra_stats || {})

  end

  def test_adds_the_vector_under_into
    records = run_embed([{"title" => "a"}], text: "title")

    assert_equal [{"title" => "a", "embedding" => vector("a")}], records
  end

  def test_into_names_another_field
    assert_equal ["vec"], run_embed([{"t" => "a"}], text: "t", into: "vec").first.keys - ["t"]
  end

  def test_joins_fields_and_skips_empty_values
    recorder = Recorder.new
    run_embed([{"title" => "a", "subjects" => ["x", "", nil, " "], "abstract" => nil, "year" => 1851}],
              provider: recorder, text: ["title", "subjects", "abstract", "year"])

    assert_equal ["a\nx\n1851"], recorder.calls.last
  end

  def test_takes_a_callable
    recorder = Recorder.new
    run_embed([{"t" => "a"}], provider: recorder, text: ->(record) { record["t"].upcase })

    assert_equal ["A"], recorder.calls.last
  end

  def test_a_callable_may_return_nil_or_blank_for_no_text
    field = ->(record) { record["t"] }
    result = Metacrunch::Testing.run(job(Recorder.new, text: field), source: [{"t" => nil}, {"t" => " "}])

    assert_equal({"No text to embed" => 2}, result.stats.marked)
  end

  def test_a_provider_with_only_embed
    minimal = Class.new { def embed(texts) = texts.map { [1.0, 0.0] } }.new
    embed = Metacrunch::Ai::Embed.new(minimal, text: "t")
    embed.open(open_context)
    results = embed.call_batch([{"t" => "a"}, {"t" => "b"}], [context, context])
    embed.close

    assert_equal([[1.0, 0.0]] * 2, results.map { it["embedding"] })
  end

  def test_close_without_open
    Metacrunch::Ai::Embed.new(Fake.new, text: "t").close
  end

  def test_a_provider_that_returns_no_array_fails_the_call
    odd = Class.new(Fake) { def embed(texts) = texts == ["metacrunch"] ? super : nil }.new

    assert_equal "the provider returned 0 vectors for 1 text", failure_of(odd).message
  end

  def test_no_text_passes_the_record_with_a_mark
    recorder = Recorder.new
    result = Metacrunch::Testing.run(job(recorder, text: "t"), source: [{"t" => ""}, {"t" => nil}])

    assert_equal [{"t" => ""}, {"t" => nil}], result.records
    assert_equal({"No text to embed" => 2}, result.stats.marked)
    assert_equal [["metacrunch"]], recorder.calls
  end

  def test_mixed_batch_maps_vectors_to_the_right_records
    recorder = Recorder.new
    records = run_embed([{"t" => "a"}, {"t" => nil}, {"t" => "b"}], provider: recorder, text: "t")

    assert_equal([vector("a"), nil, vector("b")], records.map { it["embedding"] })
    assert_equal ["a", "b"], recorder.calls.last
  end

  def test_splits_by_max_inputs
    recorder = Recorder.new(max_inputs: 2)
    run_embed((1..5).map { {"t" => it.to_s} }, provider: recorder, text: "t")

    assert_equal [1, 2, 2, 1], recorder.calls.map(&:size)
  end

  def test_invalid_input_isolates_the_culprits
    bad = ->(texts) { Metacrunch::Ai::InvalidInput.new("too long", status: 400) if texts.include?("bad") }
    recorder = Recorder.new(fail_with: bad)
    result = Metacrunch::Testing.run(job(recorder, text: "t"), source: [{"t" => "a"}, {"t" => "bad"}, {"t" => "c"}])

    assert_equal(["a", "c"], result.records.map { it["t"] })
    assert_equal([Metacrunch::Ai::InvalidInput], result.failures.map { it.last.error.class })
    assert_equal [["metacrunch"], ["a", "bad", "c"], ["a"], ["bad"], ["c"]], recorder.calls
  end

  def test_unavailable_fails_every_record_of_the_call
    down = ->(texts) { Metacrunch::Ai::Unavailable.new("down") if texts.include?("b") }
    recorder = Recorder.new(fail_with: down, max_inputs: 2)
    result = Metacrunch::Testing.run(job(recorder, text: "t"), source: ["a", "b", "c", "d"].map { {"t" => it} })

    assert_equal(["c", "d"], result.records.map { it["t"] })
    assert_equal(["a", "b"], result.failures.map { it.first["t"] })
  end

  def test_a_vector_of_another_dimension_fails_its_record
    short = Class.new(Fake) { def embed(texts) = texts == ["metacrunch"] ? super : [[1.0, 0.0, 0.0]] }.new
    error = failure_of(short)

    assert_equal [Metacrunch::Ai::Error, "vector of 3 dimensions, expected 8"], [error.class, error.message]
  end

  def test_a_vector_with_a_non_finite_number_fails_its_record
    broken = Class.new(Fake) { def embed(texts) = texts == ["metacrunch"] ? super : [[Float::NAN] * 8] }.new

    assert_equal "vector with a non-finite number or not an Array of numbers", failure_of(broken).message
  end

  def test_a_provider_with_another_count_of_vectors_fails_the_call
    greedy = Class.new(Fake) { def embed(texts) = texts == ["metacrunch"] ? super : super + super }.new

    assert_equal "the provider returned 2 vectors for 1 text", failure_of(greedy).message
  end

  def test_field_forms_need_hash_records
    error = failure_of(Fake.new, record: 42)

    assert_equal [Metacrunch::ContractError, "Embed needs Hash records for text: fields, got Integer"],
                 [error.class, error.message]
  end

  def test_an_error_of_the_callable_fails_only_its_record
    shout = ->(book) { book["title"].upcase }
    books = (1..5).map { {"title" => it == 3 ? nil : "Book #{it}"} }
    result = Metacrunch::Testing.run(job(Fake.new, text: shout), source: books)

    assert_equal(["Book 1", "Book 2", "Book 4", "Book 5"], result.records.map { it["title"] })
    assert_equal([[nil, NoMethodError]], result.failures.map { [it.first["title"], it.last.error.class] })
  end

  def test_a_field_with_invalid_utf8_fails_only_its_record
    books = [{"t" => "a"}, {"t" => (+"\xFF \xFE").force_encoding(Encoding::UTF_8)}, {"t" => "c"}]
    result = Metacrunch::Testing.run(job(Fake.new, text: "t"), source: books)

    assert_equal(["a", "c"], result.records.map { it["t"] })
    assert_equal 1, result.failures.size
  end

  def test_a_callable_must_return_a_string_or_nil
    error = failure_of(Fake.new, text: ->(_record) { 42 })

    assert_equal "text: returned Integer, expected a String or nil", error.message
  end

  def test_open_probes_and_stops_on_errors
    refusing = Recorder.new(fail_with: ->(_texts) { Metacrunch::Ai::ApiError.new("401: no key", status: 401) })
    result = Metacrunch::Testing.run(job(refusing, text: "t"), source: [{"t" => "a"}])

    assert_equal :aborted, result.status
    assert_equal "401: no key", result.error.message
  end

  def test_open_learns_the_dimension_from_the_probe
    embed = Metacrunch::Ai::Embed.new(Fake.new(dims: 12), text: "t")
    embed.open(open_context)

    assert_equal 12, embed.dims
  end

  def test_a_useless_probe_stops_at_open
    empty = Class.new(Fake) { def embed(_texts) = [[]] }.new
    error = assert_raises(Metacrunch::Ai::Error) { Metacrunch::Ai::Embed.new(empty, text: "t").open(open_context) }

    assert_equal "the provider gave no vector for the probe", error.message
  end

  def test_open_and_close_reach_the_provider
    recorder = Recorder.new
    embed = Metacrunch::Ai::Embed.new(recorder, text: "t")
    embed.open(open_context)
    embed.close

    assert_equal [[:open, Metacrunch::OpenContext], :close], recorder.events
  end

  def test_close_logs_texts_calls_and_tokens
    log = StringIO.new
    embed = Metacrunch::Ai::Embed.new(Recorder.new(max_inputs: 2, stats: {"tokens" => 12}), text: "t")
    embed.open(open_context(log))
    embed.call_batch((1..5).map { {"t" => it.to_s} }, Array.new(5) { context })
    embed.close

    assert_includes log.string, "embedded 5 texts in 3 calls, 12 tokens"
  end

  def test_close_logs_without_tokens
    log = StringIO.new
    embed = Metacrunch::Ai::Embed.new(Fake.new, text: "t")
    embed.open(open_context(log))
    embed.close

    assert_match(/embedded 0 texts in 0 calls$/, log.string)
  end

  def test_works_per_record_without_batch
    recorder = Recorder.new
    embed = Metacrunch::Ai::Embed.new(recorder, text: "t")
    job = Metacrunch.job { map embed }
    result = Metacrunch::Testing.run(job, source: [{"t" => "a"}, {"t" => "b"}])

    assert_equal([vector("a"), vector("b")], result.records.map { it["embedding"] })
    assert_equal [["metacrunch"], ["a"], ["b"]], recorder.calls
  end

  def test_per_record_failures_raise
    embed = Metacrunch::Ai::Embed.new(Fake.new, text: "t")
    embed.open(open_context)

    assert_raises(Metacrunch::ContractError) { embed.call(42, context) }
  end

  def test_in_a_job_with_workers
    job = Metacrunch.job do
      map Metacrunch::Ai::Embed.new(Metacrunch::Ai::FakeEmbedder.new, text: "t"), batch: 3
    end
    result = Metacrunch::Testing.run(job, source: (1..7).map { {"t" => it.to_s} }, workers: 2)

    assert_equal((1..7).map { vector(it.to_s) }, result.records.map { it["embedding"] })
  end

  def test_calls_for_a_large_run
    fake = Fake.new(max_inputs: 32)
    run_embed((1..1000).map { {"t" => it.to_s} }, provider: fake, text: "t", batch: 100)

    assert_equal 41, fake.stats["requests"]
  end

  def test_validates_options
    [[Object.new, {text: "t"}], [Fake.new, {text: []}], [Fake.new, {text: 1}], [Fake.new, {text: [""]}],
     [Fake.new, {text: "t", into: ""}]].each do |provider, options|
      assert_raises(ArgumentError, options.inspect) { Metacrunch::Ai::Embed.new(provider, **options) }
    end
  end

  private

  def vector(text) = Fake.new.embed([text]).first

  def job(provider, batch: 10, **)
    embed = Metacrunch::Ai::Embed.new(provider, **)
    Metacrunch.job do
      map embed, batch: batch
      on_failure :skip
    end
  end

  def run_embed(records, provider: Fake.new, batch: 10, **)
    result = Metacrunch::Testing.run(job(provider, batch:, **), source: records)
    raise result.error if result.error

    result.records
  end

  # The error the first record failed with.
  def failure_of(provider, record: {"t" => "a"}, text: "t")
    result = Metacrunch::Testing.run(job(provider, text:), source: [record])

    result.failures.first.last.error
  end

  def open_context(log = StringIO.new) = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log))

  def context = Metacrunch::Context.new(id: nil, position: 1, logger: Logger.new(nil))

end
