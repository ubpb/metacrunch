# frozen_string_literal: true

require "pp"
require "test_helper"

# Secrets with {credential: PATH} defaults, read from real encrypted
# credentials.
class ParamsCredentialsTest < Minitest::Test

  include CredentialsHelper

  SECRET = "sk-123-geheim"

  def test_the_command_line_wins_over_the_credentials
    with_credentials({"catalog" => {"api_key" => "from-credentials"}}) do |credentials|
      params = api_key_schema

      assert_equal ["from-cli", "from-credentials"],
                   [params.bind_argv(["--api-key", "from-cli"], env: {}, credentials:).api_key,
                    params.bind_argv([], env: {}, credentials:).api_key]
    end
  end

  def test_converts_credential_values_like_command_line_values
    data = {"bulk" => "42", "port" => 9200, "dry" => "yes", "tls" => true, "hosts" => ["es1", "es2"]}
    with_credentials(data) do |credentials|
      params = schema do
        secret :bulk, Integer, default: {credential: "bulk"}
        secret :port, Integer, default: {credential: "port"}
        secret :dry, :bool, default: {credential: "dry"}
        secret :tls, :bool, default: {credential: "tls"}
        secret :hosts, Array, default: {credential: "hosts"}
      end

      assert_equal({bulk: 42, port: 9200, dry: true, tls: true, hosts: ["es1", "es2"]},
                   params.bind_argv([], env: {}, credentials:).to_h)
    end
  end

  def test_values_keep_the_text_that_yaml_1_1_would_retype
    with_credentials("pin: 0123\npassword: no\nport: 0123\ndry: 1\n") do |credentials|
      params = schema do
        secret :pin, String, default: {credential: "pin"}
        secret :password, String, default: {credential: "password"}
        secret :port, Integer, default: {credential: "port"}
        secret :dry, :bool, default: {credential: "dry"}
      end

      assert_equal({pin: "0123", password: "no", port: 123, dry: true},
                   params.bind_argv([], env: {}, credentials:).to_h)
    end
  end

  def test_list_elements_must_be_texts
    with_credentials("hosts: [es1, {port: 9200}]\n") do |credentials|
      params = schema { secret :hosts, Array, default: {credential: "hosts"} }
      error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, credentials:) }

      assert_match(/\(hidden\) is not an Array of Strings/, error.message)
    end
  end

  def test_a_hash_is_no_value
    with_credentials({"catalog" => {"api_key" => {"nested" => SECRET}}}) do |credentials|
      error = assert_raises(Metacrunch::ParamError) { api_key_schema.bind_argv([], env: {}, credentials:) }

      assert_match(/\(hidden\) is not a String/, error.message)
      refute_includes error.message, SECRET
    end
  end

  def test_a_missing_credential_names_the_file
    with_credentials({"other" => 1}, environment: "production") do |credentials, dir|
      error = assert_raises(Metacrunch::ParamError) { api_key_schema.bind_argv([], env: {}, credentials:) }

      assert_equal "api_key: credential catalog.api_key from default: not in #{dir}/credentials.production.yml.enc",
                   error.message
    end
  end

  def test_a_missing_environment_file_is_named
    with_credentials({"catalog" => {"api_key" => SECRET}}) do |_credentials, dir|
      credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: dir, environment: "production")
      error = assert_raises(Metacrunch::ParamError) { api_key_schema.bind_argv([], env: {}, credentials:) }

      assert_equal "api_key: credential catalog.api_key from default: no credentials for environment production " \
                   "in #{dir}", error.message
    end
  end

  def test_a_credential_path_needs_non_empty_segments
    errors = ["", ".a", "a.", "a..b", :a].map do |path|
      assert_raises(ArgumentError) { schema { secret :x, String, default: {credential: path} } }.message
    end

    assert_equal ["secret x: a reference is {credential: PATH} or {env: NAME}"] * 5, errors
  end

  def test_help_shows_the_sources_of_a_secret_but_no_value
    required = schema { secret :api_key, String, required: true, desc: "Catalog API key" }.help

    assert_includes required, "Catalog API key (required, secret)"
    assert_includes api_key_schema.help, "(secret, default: credential catalog.api_key)"
  end

  def test_invalid_values_of_a_secret_are_hidden_from_every_source
    with_credentials({"pin" => SECRET}) do |credentials|
      params = schema { secret :pin, Integer, default: {credential: "pin"} }
      messages = [["--pin", SECRET], []].map do |argv|
        assert_raises(Metacrunch::ParamError) { params.bind_argv(argv, env: {}, credentials:) }.message
      end

      assert_equal 2, messages.grep(/\(hidden\) is not an Integer/).size
      assert_empty messages.grep(/#{SECRET}/)
    end
  end

  def test_a_hidden_value_does_not_survive_as_the_cause
    params = schema { secret :pin, Integer }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv(["--pin", SECRET], env: {}) }

    assert_nil error.cause
    refute_includes error.full_message(highlight: false), SECRET
  end

  def test_a_plain_default_of_a_secret_is_not_shown
    error = assert_raises(ArgumentError) { schema { secret :pin, Integer, default: SECRET } }

    refute_includes error.full_message(highlight: false), SECRET
  end

  def test_inspect_to_s_and_pp_show_secrets_as_secret
    params = schema do
      param :index, String
      secret :api_key, String
    end
    values = params.bind_values({index: "test", api_key: SECRET}, env: {})

    assert_equal "#<data index=\"test\", api_key=[secret]>", values.inspect
    assert_equal values.inspect, values.to_s
    assert_equal "#<data index=\"test\", api_key=[secret]>\n", values.pretty_inspect
  end

  def test_the_values_keep_the_secret
    values = api_key_schema.bind_values({api_key: SECRET}, env: {})

    assert_equal [SECRET, {api_key: SECRET}], [values.api_key, values.to_h]
  end

  def test_no_warning_for_other_parameters_and_for_values_from_the_credentials
    with_credentials({"catalog" => {"api_key" => SECRET}}) do |credentials|
      warnings = []
      params = schema do
        param :index, String
        secret :api_key, String, default: {credential: "catalog.api_key"}
      end
      params.bind_argv(["--index", "x"], env: {}, credentials:, warn: ->(message) { warnings << message })

      assert_empty warnings
    end
  end

  def test_credentials_are_read_only_when_no_earlier_source_gives_a_value
    in_tmpdir do |root|
      write_file(root, ".metacrunch/credentials.yml.enc", "garbage")
      credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: File.join(root, ".metacrunch"))
      params = api_key_schema

      assert_equal "cli", params.bind_argv(["--api-key", "cli"], env: {}, credentials:).api_key
      assert_raises(Metacrunch::CredentialsError) { params.bind_argv([], env: {}, credentials:) }
    end
  end

  def test_option_errors_do_not_echo_values
    params = schema do
      secret :api_key, String
      param :dry, :bool
    end
    errors = [["--api-ky=#{SECRET}"], ["--dry=#{SECRET}"], ["-P#{SECRET}"]].map do |argv|
      assert_raises(Metacrunch::ParamError) { params.bind_argv(argv, env: {}) }
    end

    assert_equal ["invalid option: --api-ky", "needless argument: --dry", "invalid option: -P"], errors.map(&:message)
    assert_empty errors.map { it.full_message(highlight: false) }.grep(/#{SECRET}/)
  end

  private

  def schema(&) = Metacrunch::Params.new.tap { |params| params.instance_exec(&) }

  def api_key_schema = schema { secret :api_key, String, default: {credential: "catalog.api_key"} }

  # Yields a store over credentials with data (a Hash or YAML text), and
  # the credentials directory.
  def with_credentials(data, environment: nil)
    in_tmpdir do |root|
      write_credentials(root, data, environment:)
      dir = File.join(root, ".metacrunch")
      yield Metacrunch::Credentials.store(job_file: nil, env: {}, directory: dir, environment:), dir
    end
  end

end
