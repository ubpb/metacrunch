# frozen_string_literal: true

require "test_helper"

class ParamsValuesTest < Minitest::Test

  def test_binds_typed_values_and_strings
    bound = schema.bind_values({lang: "en", limit: "5", ratio: 2, strict: true, tags: ["a"], files: ["x.xml"]})

    assert_equal ["en", 5, 2.0, true, ["a"], ["x.xml"]],
                 [bound.lang, bound.limit, bound.ratio, bound.strict, bound.tags, bound.files]
    assert_predicate bound.files, :frozen?
  end

  def test_string_keys_and_a_single_argument_work_too
    bound = schema.bind_values({"lang" => "en", "files" => "x.xml"})

    assert_equal ["en", ["x.xml"]], [bound.lang, bound.files]
  end

  def test_nil_counts_as_not_given
    bound = schema.bind_values({lang: nil, limit: nil, files: nil})

    assert_equal ["de", nil, []], [bound.lang, bound.limit, bound.files]
  end

  def test_missing_values_come_from_the_default_reference
    credentials = FakeCredentials.new("api.pin" => "7")
    pin = ->(values) { secret_schema.bind_values(values, env: {}, credentials:).pin }

    assert_equal [1, 7], [pin.call({pin: 1, code: "c"}), pin.call({code: "c"})]
  end

  def test_unknown_keys_raise_argument_errors
    messages = [schema, Metacrunch::Params.new].map do |params|
      assert_raises(ArgumentError) { params.bind_values({lnag: "en"}) }.message
    end

    assert_equal ["unknown parameter :lnag (known: lang, limit, ratio, strict, tags, files)",
                  "unknown parameter :lnag (known: none)"], messages
  end

  def test_invalid_values_are_named_by_their_name
    error = assert_raises(Metacrunch::ParamError) { schema.bind_values({limit: "many"}) }

    assert_equal "invalid value for limit: \"many\" is not an Integer", error.message
  end

  def test_invalid_secrets_stay_hidden
    error = assert_raises(Metacrunch::ParamError) { secret_schema.bind_values({pin: "abc"}, env: {}) }

    assert_equal "invalid value for pin: (hidden) is not an Integer", error.message
  end

  def test_missing_values_are_named_by_their_name
    error = assert_raises(Metacrunch::ParamError) { secret_schema.bind_values({pin: 1}, env: {}) }

    assert_equal "missing required parameter code", error.message
  end

  # Values from code are named as Ruby types; strings keep the command
  # line's wording, since they are converted like it.
  def test_type_messages_fit_the_value
    messages = [{strict: 1}, {tags: [1, 2]}, {strict: "maybe"}].map { message_for(schema, it) }

    assert_equal ["invalid value for strict: 1 is not true or false",
                  "invalid value for tags: [1, 2] is not an Array of Strings",
                  "invalid value for strict: \"maybe\" is not a boolean (true/false, yes/no, on/off, 1/0)"], messages
  end

  def test_args_take_strings_only
    messages = [{files: {a: 1}}, {files: 5}, {files: [:a]}].map { message_for(schema, it) }

    assert_equal ["invalid value for files: {a: 1} is not an Array of Strings",
                  "invalid value for files: 5 is not an Array of Strings",
                  "invalid value for files: [:a] is not an Array of Strings"], messages
  end

  def test_args_keep_their_limits
    at_least_one = Metacrunch::Params.new.tap { it.args :files, min: 1 }
    error = assert_raises(Metacrunch::ParamError) { at_least_one.bind_values({}) }

    assert_equal "expected at least 1 argument(s) for files, got 0", error.message
  end

  def test_the_command_line_still_names_options
    error = assert_raises(Metacrunch::ParamError) { secret_schema.bind_argv(["--pin", "1"], env: {}) }

    assert_equal "missing required parameter --code", error.message
  end

  def test_pathnames_count_as_strings
    bound = schema.bind_values({lang: Pathname("en"), tags: [Pathname("a"), "b"], files: [Pathname("x.xml")]})

    assert_equal ["en", ["a", "b"], ["x.xml"]], [bound.lang, bound.tags, bound.files]
  end

  def test_a_single_pathname_argument_works_too
    assert_equal ["x.xml"], schema.bind_values({files: Pathname("x.xml")}).files
  end

  def test_values_must_be_a_hash
    error = assert_raises(ArgumentError) { schema.bind_values([[:lang, "en"]]) }

    assert_equal "params: must be a Hash, got [[:lang, \"en\"]]", error.message
  end

  private

  # The ParamError message for values bound to params, or nil without one.
  def message_for(params, values)
    params.bind_values(values)
    nil
  rescue Metacrunch::ParamError => e
    e.message
  end

  def schema
    Metacrunch::Params.new.tap do |params|
      params.param :lang, String, default: "de"
      params.param :limit, Integer
      params.param :ratio, Float
      params.param :strict, :bool, default: false
      params.param :tags, Array
      params.args :files
    end
  end

  # pin comes first, so a test can reach its invalid value before code is
  # found missing.
  def secret_schema
    Metacrunch::Params.new.tap do |params|
      params.secret :pin, Integer, default: {credential: "api.pin"}
      params.secret :code, String, required: true
    end
  end

end
