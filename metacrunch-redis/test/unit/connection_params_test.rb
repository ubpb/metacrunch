# frozen_string_literal: true

require "test_helper"

class ConnectionParamsTest < Minitest::Test

  def test_connection_params_declare_url_user_and_password
    definitions = declared(Metacrunch::Redis::CONNECTION_PARAMS)

    assert_equal [:url, :user, :password], definitions.keys
    assert_equal [true, false, false], definitions.values.map(&:required)
    assert_equal [false, false, true], definitions.values.map(&:secret?)
  end

  def test_the_url_param_shows_examples
    assert_equal "Redis URL, e.g. redis://localhost:6379/0 or rediss://host:6380/1",
                 declared(Metacrunch::Redis::CONNECTION_PARAMS)[:url].desc
  end

  def test_a_prefix_names_the_params_and_descriptions
    definitions = declared(Metacrunch::Redis.connection_params("target"))

    assert_equal [:target_url, :target_user, :target_password], definitions.keys
    assert_predicate definitions[:target_password], :secret?
    assert(definitions.values.all? { it.desc.include?("target Redis") })
  end

  def test_a_bad_prefix_is_refused
    ["Target", "1x", "", "a-b", :target].each do |prefix|
      error = assert_raises(ArgumentError) { Metacrunch::Redis.connection_params(prefix) }

      assert_equal "prefix must be a lowercase word such as target, got #{prefix.inspect}", error.message
    end
  end

  private

  def declared(declarations) = Metacrunch::Params.new.tap { it.use(declarations) }.definitions

end
