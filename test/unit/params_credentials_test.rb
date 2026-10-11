# frozen_string_literal: true

require "pp"
require "test_helper"

class ParamsCredentialsTest < Minitest::Test

  include CredentialsHelper

  SECRET = "sk-123-geheim"

  def test_the_command_line_wins_over_env_and_credentials
    with_credentials({"fis" => {"api_key" => "from-credentials"}}) do |credentials|
      params = api_key_schema
      env = {"FIS_API_KEY" => "from-env"}

      assert_equal "from-cli", params.bind_argv(["--api-key", "from-cli"], env:, credentials:).api_key
      assert_equal "from-env", params.bind_argv([], env:, credentials:).api_key
      assert_equal "from-credentials", params.bind_argv([], env: {"FIS_API_KEY" => ""}, credentials:).api_key
    end
  end

  def test_the_default_comes_last
    with_credentials({}) do |credentials|
      assert_equal "from-default", api_key_schema(default: "from-default").bind_argv([], env: {}, credentials:).api_key
    end
  end

  def test_converts_credential_values_like_command_line_values
    data = {"bulk" => "42", "port" => 9200, "dry" => "yes", "tls" => true, "hosts" => ["es1", "es2"]}
    with_credentials(data) do |credentials|
      params = schema do
        param :bulk, Integer, credential: "bulk"
        param :port, Integer, credential: "port"
        param :dry, :bool, credential: "dry"
        param :tls, :bool, credential: "tls"
        param :hosts, Array, credential: "hosts"
      end

      assert_equal({bulk: 42, port: 9200, dry: true, tls: true, hosts: ["es1", "es2"]},
                   params.bind_argv([], env: {}, credentials:).to_h)
    end
  end

  def test_values_keep_the_text_that_yaml_1_1_would_retype
    with_credentials("pin: 0123\npassword: no\nport: 0123\ndry: 1\n") do |credentials|
      params = schema do
        param :pin, String, credential: "pin"
        param :password, String, credential: "password"
        param :port, Integer, credential: "port"
        param :dry, :bool, credential: "dry"
      end

      assert_equal({pin: "0123", password: "no", port: 123, dry: true},
                   params.bind_argv([], env: {}, credentials:).to_h)
    end
  end

  def test_list_elements_must_be_texts
    with_credentials("hosts: [es1, {port: 9200}]\n") do |credentials|
      params = schema { param :hosts, Array, credential: "hosts" }
      error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, credentials:) }

      assert_match(/\(hidden\) is not a comma-separated list/, error.message)
    end
  end

  def test_a_hash_is_no_value
    with_credentials({"fis" => {"api_key" => {"nested" => SECRET}}}) do |credentials|
      error = assert_raises(Metacrunch::ParamError) { api_key_schema.bind_argv([], env: {}, credentials:) }

      assert_match(/\(hidden\) is not a String/, error.message)
      refute_includes error.message, SECRET
    end
  end

  def test_a_missing_required_value_names_every_source
    with_credentials({"other" => 1}, environment: "production") do |credentials, dir|
      error = assert_raises(Metacrunch::ParamError) do
        api_key_schema(required: true).bind_argv([], env: {}, credentials:)
      end

      assert_equal "missing required parameter --api-key (FIS_API_KEY unset; fis.api_key not in " \
                   "#{dir}/credentials.production.yml.enc)", error.message
    end
  end

  def test_a_missing_environment_file_is_named
    with_credentials({"fis" => {"api_key" => SECRET}}) do |_credentials, dir|
      credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: dir, environment: "production")
      error = assert_raises(Metacrunch::ParamError) do
        api_key_schema(required: true).bind_argv([], env: {}, credentials:)
      end

      assert_equal "missing required parameter --api-key (FIS_API_KEY unset; no credentials for environment " \
                   "production in #{dir})", error.message
    end
  end

  def test_without_credentials_the_message_says_so
    params = schema { param :api_key, String, credential: "fis.api_key", required: true }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}) }

    assert_equal "missing required parameter --api-key (fis.api_key: no credentials)", error.message
  end

  def test_a_missing_value_names_the_unset_variable
    params = schema { param :url, String, env: "ES_URL", required: true }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}) }

    assert_equal "missing required parameter --url (ES_URL unset)", error.message
  end

  def test_a_credential_path_needs_non_empty_segments
    errors = ["", ".a", "a.", "a..b", :a].map do |path|
      assert_raises(ArgumentError) { schema { param :x, String, credential: path } }.message
    end

    assert_equal "parameter x: credential must be a path like \"fis.api_key\", got \"\"", errors.first
    assert_equal 5, errors.grep(/credential must be a path/).size
  end

  def test_help_shows_the_sources_of_a_secret_but_no_value
    help = api_key_schema(required: true, desc: "FIS API key").help

    assert_includes help, "FIS API key (required, secret, env: FIS_API_KEY, credential: fis.api_key)"
  end

  def test_help_hides_the_default_of_a_secret
    help = api_key_schema(default: SECRET).help

    refute_includes help, SECRET
    assert_includes help, "(secret, env: FIS_API_KEY, credential: fis.api_key)"
  end

  def test_invalid_values_of_a_secret_are_hidden_from_every_source
    with_credentials({"pin" => SECRET}) do |credentials|
      params = schema { param :pin, Integer, env: "PIN", credential: "pin" }
      messages = [[["--pin", SECRET], {}], [[], {"PIN" => SECRET}], [[], {}]].map do |argv, env|
        assert_raises(Metacrunch::ParamError) { params.bind_argv(argv, env:, credentials:) }.message
      end

      assert_equal 3, messages.grep(/\(hidden\) is not an Integer/).size
      assert_empty messages.grep(/#{SECRET}/)
    end
  end

  def test_a_hidden_value_does_not_survive_as_the_cause
    params = schema { param :pin, Integer, env: "PIN", credential: "pin" }
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {"PIN" => SECRET}) }

    assert_nil error.cause
    refute_includes error.full_message(highlight: false), SECRET
  end

  def test_a_hidden_default_does_not_survive_as_the_cause
    error = assert_raises(ArgumentError) { schema { param :pin, Integer, credential: "pin", default: SECRET } }

    refute_includes error.full_message(highlight: false), SECRET
  end

  def test_an_invalid_default_of_a_secret_is_hidden
    error = assert_raises(ArgumentError) { schema { param :pin, Integer, credential: "pin", default: SECRET } }

    assert_equal "invalid default for parameter pin: (hidden) is not an Integer", error.message
  end

  def test_inspect_to_s_and_pp_show_secrets_as_secret
    params = schema do
      param :index, String
      param :api_key, String, credential: "fis.api_key"
    end
    values = params.bind_hash(index: "test", api_key: SECRET)

    assert_equal "#<data index=\"test\", api_key=[secret]>", values.inspect
    assert_equal values.inspect, values.to_s
    assert_equal "#<data index=\"test\", api_key=[secret]>\n", values.pretty_inspect
  end

  def test_the_values_keep_the_secret
    values = api_key_schema.bind_hash(api_key: SECRET)

    assert_equal [SECRET, {api_key: SECRET}], [values.api_key, values.to_h]
  end

  def test_warns_about_a_secret_on_the_command_line
    warnings = []
    api_key_schema.bind_argv(["--api-key", SECRET], env: {}, warn: ->(message) { warnings << message })

    assert_equal ["--api-key is a secret; pass it by FIS_API_KEY or credentials instead"], warnings
  end

  def test_without_env_the_warning_names_only_the_credentials
    warnings = []
    params = schema { param :api_key, String, credential: "fis.api_key" }
    params.bind_argv(["--api-key", SECRET], env: {}, warn: ->(message) { warnings << message })

    assert_equal ["--api-key is a secret; pass it by credentials instead"], warnings
  end

  def test_no_warning_for_other_parameters_and_for_values_from_env
    warnings = []
    params = schema do
      param :index, String
      param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key"
    end
    params.bind_argv(["--index", "x"], env: {"FIS_API_KEY" => SECRET}, warn: ->(message) { warnings << message })

    assert_empty warnings
  end

  def test_credentials_are_read_only_when_command_line_and_env_give_no_value
    in_tmpdir do |root|
      write_file(root, ".metacrunch/credentials.yml.enc", "garbage")
      credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: File.join(root, ".metacrunch"))
      params = api_key_schema

      assert_equal "cli", params.bind_argv(["--api-key", "cli"], env: {}, credentials:).api_key
      assert_equal "env", params.bind_argv([], env: {"FIS_API_KEY" => "env"}, credentials:).api_key
      assert_raises(Metacrunch::CredentialsError) { params.bind_argv([], env: {}, credentials:) }
    end
  end

  def test_option_errors_do_not_echo_values
    params = schema do
      param :api_key, String, credential: "fis.api_key"
      param :dry, :bool
    end
    errors = [["--api-ky=#{SECRET}"], ["--dry=#{SECRET}"]].map do |argv|
      assert_raises(Metacrunch::ParamError) { params.bind_argv(argv, env: {}) }
    end

    assert_equal ["invalid option: --api-ky", "needless argument: --dry"], errors.map(&:message)
    assert_empty errors.map { it.full_message(highlight: false) }.grep(/#{SECRET}/)
  end

  def test_bind_hash_ignores_credentials
    assert_nil api_key_schema.bind_hash({}).api_key
  end

  private

  def schema(&) = Metacrunch::Params.new.tap { |params| params.instance_exec(&) }

  def api_key_schema(**options)
    settings = {env: "FIS_API_KEY", credential: "fis.api_key"}.merge(options)
    schema { param :api_key, String, **settings }
  end

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
