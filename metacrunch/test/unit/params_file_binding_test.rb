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

  def test_the_file_wins_over_a_credential
    params = schema { param :index, String, credential: "x.index" }
    credentials = FakeCredentials.new("x.index" => "cred")

    assert_equal "f", params.bind_argv([], env: {}, credentials:, file: params_file("default: {index: f}\n")).index
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

    assert_equal "sk", schema { param :api_key }.bind_argv([], env: {}, credentials:, file:).api_key
  end

  def test_a_value_from_the_credentials_is_hidden
    file = params_file("default: {api_key: {credential: catalog.api_key}}\n")
    credentials = FakeCredentials.new("catalog.api_key" => "sk")
    inspected = schema { param :api_key }.bind_argv([], env: {}, credentials:, file:).inspect

    assert_includes inspected, "api_key=[secret]"
    refute_includes inspected, "sk"
  end

  def test_an_invalid_value_from_the_credentials_is_hidden
    file = params_file("default: {port: {credential: catalog.port}}\n")
    credentials = FakeCredentials.new("catalog.port" => "x")
    error = assert_raises(Metacrunch::ParamError) do
      schema { param :port, Integer }.bind_argv([], env: {}, credentials:, file:)
    end

    assert_equal "invalid value for port from credential catalog.port in test: (hidden) is not an Integer",
                 error.message
  end

  def test_a_missing_reference_fails
    file = params_file("default: {api_key: {credential: catalog.api_key}}\n")
    params = schema { param :api_key }
    missing = assert_raises(Metacrunch::ParamError) do
      params.bind_argv([], env: {}, credentials: FakeCredentials.new({}), file:)
    end
    none = assert_raises(Metacrunch::ParamError) { params.bind_argv([], env: {}, file:) }

    assert_equal ["api_key from #{file.path} (default): catalog.api_key not in test",
                  "api_key from #{file.path} (default): no credentials"], [missing.message, none.message]
  end

  def test_a_reference_converts_lists
    file = params_file("default: {hosts: {credential: es.hosts}}\n")
    credentials = FakeCredentials.new("es.hosts" => ["es1", "es2"])

    assert_equal ["es1", "es2"], schema { param :hosts, Array }.bind_argv([], env: {}, credentials:, file:).hosts
  end

  def test_a_plain_value_for_a_secret_warns
    file = params_file("default: {api_key: plain}\n")
    warnings = []
    params = schema { param :api_key, String, credential: "catalog.api_key" }

    assert_equal "plain", params.bind_argv([], env: {}, file:, warn: ->(message) { warnings << message }).api_key
    assert_equal ["api_key is a secret; refer to it in #{file.path} as {credential: catalog.api_key}"], warnings
  end

  def test_other_bindings_keep_their_secrets
    params = schema { param :api_key }
    file = params_file("default: {api_key: {credential: catalog.api_key}}\n")
    params.bind_argv([], env: {}, credentials: FakeCredentials.new("catalog.api_key" => "sk"), file:)

    assert_includes params.bind_argv(["--api-key", "visible"], env: {}).inspect, %(api_key="visible")
  end

  # A job file may define SECRETS at the top level; it is no declared
  # secret of a parameter.
  def test_a_top_level_secrets_constant_changes_nothing
    Object.const_set(:SECRETS, ["index"].freeze)
    params = schema { param :index, String, default: "d" }
    file = params_file("default: {api_key: {credential: catalog.api_key}}\n")
    credentials = FakeCredentials.new("catalog.api_key" => "sk")
    secret = schema { param :api_key }.bind_argv([], env: {}, credentials:, file:)

    assert_equal "d", params.bind_argv([], env: {}).index
    assert_includes secret.inspect, "api_key=[secret]"
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
