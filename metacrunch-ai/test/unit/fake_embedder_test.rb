# frozen_string_literal: true

require "test_helper"

class FakeEmbedderTest < Minitest::Test

  def test_vectors_are_unit_vectors_of_dims_floats
    vector = Metacrunch::Ai::FakeEmbedder.new(dims: 16).embed(["Moby-Dick"]).first

    assert_equal 16, vector.size
    assert(vector.all?(Float))
    assert_in_delta 1.0, Math.sqrt(vector.sum { it * it }), 1e-9
  end

  def test_vectors_are_deterministic
    first, again, other = Metacrunch::Ai::FakeEmbedder.new.embed(["Moby-Dick", "Moby-Dick", "Walden"])

    assert_equal first, again
    refute_equal first, other
  end

  def test_the_same_text_gives_the_same_vector_in_another_embedder
    assert_equal Metacrunch::Ai::FakeEmbedder.new.embed(["a"]), Metacrunch::Ai::FakeEmbedder.new.embed(["a"])
  end

  def test_defaults_are_eight_dimensions_and_32_inputs
    embedder = Metacrunch::Ai::FakeEmbedder.new

    assert_equal [8, 32], [embedder.dims, embedder.max_inputs]
    assert_equal 8, embedder.embed(["x"]).first.size
  end

  def test_more_dimensions_than_a_digest_has_bytes
    vector = Metacrunch::Ai::FakeEmbedder.new(dims: 100).embed(["x"]).first

    assert_equal 100, vector.size
    assert_in_delta 1.0, Math.sqrt(vector.sum { it * it }), 1e-9
  end

  def test_counts_requests
    embedder = Metacrunch::Ai::FakeEmbedder.new
    2.times { embedder.embed(["a"]) }

    assert_equal({"requests" => 2}, embedder.stats)
  end

  def test_refuses_more_than_max_inputs
    error = assert_raises(ArgumentError) { Metacrunch::Ai::FakeEmbedder.new(max_inputs: 2).embed(["a", "b", "c"]) }

    assert_equal "at most 2 texts per call (max_inputs), got 3", error.message
  end

  def test_validates_dims_and_max_inputs
    [0, -1, "8", 1.5].each do |value|
      assert_raises(ArgumentError) { Metacrunch::Ai::FakeEmbedder.new(dims: value) }
      assert_raises(ArgumentError) { Metacrunch::Ai::FakeEmbedder.new(max_inputs: value) }
    end
  end

end
