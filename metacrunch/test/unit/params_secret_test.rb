# frozen_string_literal: true

require "test_helper"

class ParamsSecretTest < Minitest::Test

  # Credentials that must not be read, for help texts.
  class UnreadCredentials

    def lookup(_path) = raise("credentials read")

  end

  def test_a_secret_is_hidden_in_inspect_messages_and_help
    api_key = schema { secret :api_key }.bind_argv(["--api-key", "sk"], env: {})
    port = schema { secret :port, Integer }
    error = assert_raises(Metacrunch::ParamError) { port.bind_argv(["--port", "x"], env: {}) }

    assert_equal ["#<data api_key=[secret]>", "invalid value for --port: (hidden) is not an Integer"],
                 [api_key.inspect, error.message]
    assert_match(/--port VALUE +\(secret\)/, port.help)
  end

  def test_a_secret_on_the_command_line_warns
    warnings = []
    schema { secret :api_key }.bind_argv(["--api-key", "sk"], env: {}, warn: ->(message) { warnings << message })

    assert_equal ["--api-key is a secret; give it in a params file as {credential: PATH} or {env: NAME}"], warnings
  end

  def test_bind_values_takes_plain_values_for_secrets_silently
    assert_equal "x", schema { secret :api_key }.bind_values({api_key: "x"}, env: {}).api_key
  end

  def test_a_secret_default_must_be_a_reference
    error = assert_raises(ArgumentError) { schema { secret :api_key, default: "abc" } }

    assert_equal "secret api_key: a default must be {credential: PATH} or {env: NAME}, not a plain value", error.message
  end

  def test_a_credential_reference_needs_a_secret
    error = assert_raises(ArgumentError) { schema { param :index, default: {credential: "x.y"} } }

    assert_equal "parameter index: a value from the credentials needs secret, not param", error.message
  end

  def test_reference_shapes_are_checked_when_declared
    messages = [{credential: "a..b"}, {env: "1X"}, {env: "A", x: 1}, {other: "x"}].map do |default|
      assert_raises(ArgumentError, default.inspect) { schema { param :es_url, default: } }.message
    end

    assert_equal ["parameter es_url: a reference is {credential: PATH} or {env: NAME}"] * 4, messages
  end

  def test_a_secret_names_itself_in_declaration_errors
    error = assert_raises(ArgumentError) { schema { secret :api_key, default: {"credential" => 42} } }

    assert_equal "secret api_key: a reference is {credential: PATH} or {env: NAME}", error.message
  end

  def test_default_references_resolve
    params = schema do
      secret :api_key, default: {credential: "catalog.api_key"}
      param :es_url, default: {"env" => "ES_URL"}
      param :port, Integer, default: {env: "PORT"}
    end
    bound = params.bind_argv([], env: {"ES_URL" => "http://es", "PORT" => "9200"},
                                 credentials: FakeCredentials.new("catalog.api_key" => "sk"))

    assert_equal({api_key: "sk", es_url: "http://es", port: 9200}, bound.to_h)
  end

  def test_a_reference_that_finds_nothing_fails
    credential = schema { secret :api_key, default: {credential: "catalog.api_key"} }
    variable = schema { param :es_url, default: {env: "ES_URL"} }
    messages = [
      assert_raises(Metacrunch::ParamError) { credential.bind_argv([], env: {}, credentials: FakeCredentials.new({})) },
      assert_raises(Metacrunch::ParamError) { variable.bind_argv([], env: {"ES_URL" => ""}) }
    ].map(&:message)

    assert_equal ["api_key: credential catalog.api_key from default: not in test",
                  "es_url: environment variable ES_URL from default: is not set"], messages
  end

  def test_testing_reads_no_credentials_or_variables
    credential = schema { secret :api_key, default: {credential: "catalog.api_key"} }
    variable = schema { param :es_url, default: {env: "ES_URL"} }
    messages = [
      assert_raises(Metacrunch::ParamError) { credential.bind_values({}, env: nil, credentials: nil) },
      assert_raises(Metacrunch::ParamError) { variable.bind_values({}, env: nil, credentials: nil) }
    ].map(&:message)

    assert_equal ["api_key: Testing reads no credentials; pass api_key in params:",
                  "es_url: Testing reads no environment variables; pass es_url in params:"], messages
  end

  def test_an_invalid_value_from_a_reference_is_named_by_its_source
    params = schema { secret :port, Integer, default: {credential: "catalog.port"} }
    error = assert_raises(Metacrunch::ParamError) do
      params.bind_argv([], env: {}, credentials: FakeCredentials.new("catalog.port" => "x"))
    end

    assert_equal "invalid value for port from credential catalog.port in test via default: (hidden) is not an Integer",
                 error.message
  end

  def test_help_shows_sources_not_values
    help = schema do
      secret :api_key, default: {credential: "catalog.api_key"}
      param :es_url, default: {env: "ES_URL"}
    end.help

    assert_match(/--api-key VALUE +\(secret, default: credential catalog.api_key\)/, help)
    assert_match(/--es-url VALUE +\(default: env ES_URL\)/, help)
  end

  def test_the_command_line_wins_without_reading_the_reference
    params = schema { secret :api_key, default: {credential: "catalog.api_key"} }

    assert_equal "cli", params.bind_argv(["--api-key", "cli"], env: {}, credentials: UnreadCredentials.new).api_key
  end

  def test_secrets_are_not_deduplicated
    bound = schema do
      secret :api_key
      param :index
    end.bind_argv(["--api-key", "same", "--index", "same"], env: {})

    refute_same bound.api_key, bound.index
    assert_predicate bound.api_key, :frozen?
  end

  private

  def schema(&) = Metacrunch::Params.new.tap { it.instance_eval(&) }

end
