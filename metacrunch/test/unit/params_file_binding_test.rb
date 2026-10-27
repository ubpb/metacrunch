# frozen_string_literal: true

require "test_helper"

class ParamsFileBindingTest < Minitest::Test

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_the_order_of_the_sources
    params = schema { param :index, String, env: "INDEX", default: "d" }
    file = params_file("default: {index: f}\n")

    values = [
      params.bind_argv(["--index", "c"], env: {"INDEX" => "e"}, file:),
      params.bind_argv([], env: {"INDEX" => "e"}, file:),
      params.bind_argv([], env: {"INDEX" => "e"}),
      params.bind_argv([], env: {})
    ].map(&:index)

    assert_equal ["c", "f", "e", "d"], values
  end

  def test_the_file_wins_over_a_default_reference
    params = schema { secret :index, String, default: {credential: "x.index"} }
    credentials = FakeCredentials.new("x.index" => "cred")
    file = params_file("default: {index: {env: INDEX}}\n")

    assert_equal "f", params.bind_argv([], env: {"INDEX" => "f"}, credentials:, file:).index
  end

  def test_converts_like_command_line_values
    params = schema do
      param :batch, Integer
      param :dry, :bool
      param :id, String
      param :tags, Array
      param :hosts, Array
    end
    file = params_file("default: {batch: 1000, dry: no, id: 0123, tags: 'a, b', hosts: [es1, es2]}\n")

    assert_equal({batch: 1000, dry: false, id: "0123", tags: ["a", "b"], hosts: ["es1", "es2"]},
                 params.bind_argv([], env: {}, file:).to_h)
  end

  def test_null_falls_through
    params = schema { param :index, String, env: "INDEX" }
    file = params_file("default: {index: f}\nproduction: {index: ~}\n")

    assert_equal "e", params.bind_argv([], env: {"INDEX" => "e"}, file:, environment: "production").index
  end

  def test_unknown_keys_in_any_section_fail
    params = schema do
      param :output, String
      param :batch, Integer
    end
    file = params_file("default: {batch: 1}\nstaging: {outptu: x}\n")
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:) }

    assert_equal "#{file.path}: staging.outptu: unknown parameter (known: output, batch)", error.message
  end

  def test_keys_spelled_as_options_are_unknown
    file = params_file("default: {api-key: x}\n")
    error = assert_raises(Metacrunch::ParamError) { schema { param :api_key }.bind_argv([], env: {}, file:) }

    assert_equal "#{file.path}: default.api-key: unknown parameter (known: api_key)", error.message
  end

  def test_a_job_without_parameters_takes_no_keys
    file = params_file("default: {index: x}\n")
    error = assert_raises(Metacrunch::ParamError) { Metacrunch::Params.new.bind_argv([], env: {}, file:) }

    assert_equal "#{file.path}: default.index: unknown parameter (known: none)", error.message
  end

  # A flat file without sections: a reference or a null at the top level
  # reads as a section named like the parameter.
  def test_a_parameter_at_the_top_level_is_named
    params = schema do
      param :api_key
      param :index
    end
    messages = ["api_key: {credential: catalog.api_key}\n", "index:\n"].map do |content|
      file = params_file(content)
      assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:) }.message.sub(file.path, "FILE")
    end

    assert_equal ["FILE: api_key is a parameter, not a section: parameters go under default: or an environment section",
                  "FILE: index is a parameter, not a section: parameters go under default: or an environment section"],
                 messages
  end

  # An environment may be named like a parameter.
  def test_an_environment_named_like_a_parameter_is_a_section
    params = schema do
      param :test, :bool, default: false
      param :index
    end
    file = params_file("test: {index: t}\n")

    assert_equal "t", params.bind_argv([], env: {}, file:, environment: "test").index
  end

  def test_a_parameter_named_default_keeps_the_default_section
    params = schema do
      param :default
      param :index
    end
    file = params_file("default:\nproduction: {index: p}\n")

    assert_equal "p", params.bind_argv([], env: {}, file:, environment: "production").index
  end

  def test_positional_arguments_cannot_come_from_the_file
    params = schema { args :files }
    file = params_file("default: {files: [a.json]}\n")
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:) }

    assert_equal "#{file.path}: default.files: arguments cannot be given in a params file", error.message
  end

  def test_an_invalid_value_names_file_and_section
    params = schema { param :batch, Integer }
    file = params_file("default: {batch: 1}\nproduction: {batch: x}\n")
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:, environment: "production") }

    assert_equal %(invalid value for batch from #{file.path} (production): "x" is not an Integer), error.message
  end

  def test_a_list_for_a_scalar_parameter_is_invalid
    file = params_file("default: {index: [a]}\n")
    error = assert_raises(Metacrunch::ParamError) { schema { param :index }.bind_argv([], env: {}, file:) }

    assert_equal %(invalid value for index from #{file.path} (default): ["a"] is not a String), error.message
  end

  def test_the_selected_environment_is_used
    params = schema { param :index, String }
    file = params_file("default: {index: d}\nproduction: {index: p}\n")

    assert_equal "p", params.bind_argv([], env: {}, file:, environment: "production").index
    assert_equal "d", params.bind_argv([], env: {}, file:).index
  end

  def test_a_reference_reads_the_credentials
    file = params_file("default: {api_key: {credential: catalog.api_key}}\n")
    credentials = FakeCredentials.new("catalog.api_key" => "sk")
    bound = schema { secret :api_key }.bind_argv([], env: {}, credentials:, file:)

    assert_equal "sk", bound.api_key
    assert_equal "#<data api_key=[secret]>", bound.inspect
  end

  def test_an_invalid_value_from_the_credentials_is_hidden
    file = params_file("default: {port: {credential: catalog.port}}\n")
    credentials = FakeCredentials.new("catalog.port" => "x")
    error = assert_raises(Metacrunch::ParamError) do
      schema { secret :port, Integer }.bind_argv([], env: {}, credentials:, file:)
    end

    assert_equal "invalid value for port from credential catalog.port in test via #{file.path} (default): (hidden) " \
                 "is not an Integer", error.message
  end

  def test_a_missing_reference_fails
    file = params_file("default: {api_key: {credential: catalog.api_key}}\n")
    error = assert_raises(Metacrunch::ParamError) do
      schema { secret :api_key }.bind_argv([], env: {}, credentials: FakeCredentials.new({}), file:)
    end

    assert_equal "api_key: credential catalog.api_key from #{file.path} (default): not in test", error.message
  end

  def test_a_reference_converts_lists
    file = params_file("default: {hosts: {credential: es.hosts}}\n")
    credentials = FakeCredentials.new("es.hosts" => ["es1", "es2"])

    assert_equal ["es1", "es2"], schema { secret :hosts, Array }.bind_argv([], env: {}, credentials:, file:).hosts
  end

  def test_env_references_in_the_file
    params = schema { param :es_url }
    file = params_file("production: {es_url: {env: ES_URL}}\n")
    error = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:, environment: "production") }
    bound = params.bind_argv([], env: {"ES_URL" => "http://es"}, file:, environment: "production")

    assert_equal "http://es", bound.es_url
    assert_equal "es_url: environment variable ES_URL from #{file.path} (production) is not set", error.message
  end

  def test_a_credential_reference_for_a_param_in_the_file_fails
    file = params_file("default: {index: x}\nstaging: {index: {credential: catalog.index}}\n")
    error = assert_raises(Metacrunch::ParamError) { schema { param :index }.bind_argv([], env: {}, file:) }

    assert_equal "#{file.path}: staging.index: a value from the credentials needs secret, not param", error.message
  end

  def test_a_plain_value_for_a_secret_in_the_file_fails
    file = params_file("default: {api_key: {env: API_KEY}}\nstaging: {api_key: plain}\n")
    error = assert_raises(Metacrunch::ParamError) do
      schema { secret :api_key }.bind_argv([], env: {"API_KEY" => "k"}, file:)
    end

    assert_equal "#{file.path}: staging.api_key: api_key is a secret; give it as {credential: PATH} or {env: NAME}",
                 error.message
  end

  def test_plain_values_are_checked_in_every_section
    file = params_file("default: {batch: 1}\nstaging: {batch: x}\n")
    error = assert_raises(Metacrunch::ParamError) { schema { param :batch, Integer }.bind_argv([], env: {}, file:) }

    assert_equal %(invalid value for batch from #{file.path} (staging): "x" is not an Integer), error.message
  end

  def test_references_resolve_only_in_the_selected_section
    file = params_file("production: {api_key: {credential: catalog.api_key}}\nstaging: {api_key: {credential: nope}}\n")
    credentials = FakeCredentials.new("catalog.api_key" => "sk")
    bound = schema { secret :api_key }.bind_argv([], env: {}, credentials:, file:, environment: "production")

    assert_equal "sk", bound.api_key
  end

  def test_file_values_are_named_by_name_command_line_values_by_option
    params = schema { param :batch, Integer }
    file = params_file("default: {batch: x}\n")
    messages = [
      assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:) },
      assert_raises(Metacrunch::ParamError) { params.bind_argv(["--batch", "y"], env: {}) }
    ].map { it.message[/invalid value for ([^\s:]+)/, 1] }

    assert_equal ["batch", "--batch"], messages
  end

  # A job file may define SECRETS at the top level; it is no declared
  # secret of a parameter.
  def test_a_top_level_secrets_constant_changes_nothing
    Object.const_set(:SECRETS, ["index"].freeze)
    params = schema { param :index, String, default: "d" }

    assert_equal %(#<data index="d">), params.bind_argv([], env: {}).inspect
  ensure
    Object.send(:remove_const, :SECRETS) if Object.const_defined?(:SECRETS, false)
  end

  private

  def schema(&)
    Metacrunch::Params.new.tap { it.instance_eval(&) }
  end

  def params_file(content)
    path = File.join(@dir, "params.yml")
    File.write(path, content)
    Metacrunch::ParamsFile.load(path)
  end

end
