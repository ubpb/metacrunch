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
