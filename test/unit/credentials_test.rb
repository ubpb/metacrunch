# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CredentialsTest < Minitest::Test

  Credentials = Metacrunch::Credentials
  PATH = "/p/.metacrunch/credentials.yml.enc"

  YAML_ERRORS = {
    "a: [\n" => "invalid YAML in #{PATH} at line 2, column 1",
    "- a\n" => "#{PATH} must contain a mapping at the top level",
    "d: 2026-10-11\n" => "unsupported value in #{PATH}: Date (quote it)",
    "s: :sym\n" => "unsupported value in #{PATH}: Symbol (quote it)",
    "a: *missing\n" => "invalid YAML in #{PATH}"
  }.freeze

  def test_names_files_and_keys_per_environment
    assert_equal ["credentials.yml.enc", "master.key"], [Credentials.file_name(nil), Credentials.key_name(nil)]
    assert_equal ["credentials.production.yml.enc", "master.production.key"],
                 [Credentials.file_name("production"), Credentials.key_name("production")]
  end

  def test_the_environment_comes_from_the_option_then_the_variable
    env = {"METACRUNCH_ENV" => "production"}

    assert_equal "staging", Credentials.environment("staging", env)
    assert_equal "production", Credentials.environment(nil, env)
    assert_nil Credentials.environment("", {"METACRUNCH_ENV" => ""})
  end

  def test_environment_names_are_limited_to_a_to_z_digits_underscore_and_dash
    messages = ["Production", "prod.x", "../x", "a b"].map do |name|
      assert_raises(Metacrunch::CredentialsError) { Credentials.environment(name, {}) }.message
    end

    assert_equal "invalid environment \"Production\": use a-z, 0-9, _ and -", messages.first
    assert_equal 4, messages.grep(/\Ainvalid environment /).size
  end

  def test_reads_plain_yaml_types_and_aliases
    data = Credentials.load_yaml("x: &k v\ny: *k\nn: 1\nok: true\nl: [a, b]\n", PATH)

    assert_equal({"x" => "v", "y" => "v", "n" => 1, "ok" => true, "l" => ["a", "b"]}, data)
  end

  def test_a_file_with_only_comments_is_empty
    assert_equal({}, Credentials.load_yaml("# nothing yet\n", PATH))
  end

  def test_reports_yaml_errors_by_position_only
    YAML_ERRORS.each do |text, message|
      error = assert_raises(Metacrunch::CredentialsError) { Credentials.load_yaml(text, PATH) }

      assert_equal message, error.message, text
    end
  end

  def test_yaml_errors_keep_no_psych_error_as_the_cause
    error = assert_raises(Metacrunch::CredentialsError) { Credentials.load_yaml("a: *geheim\n", PATH) }

    assert_nil error.cause
  end

  def test_yaml_errors_do_not_quote_the_content
    error = assert_raises(Metacrunch::CredentialsError) { Credentials.load_yaml("password: \"geheim\n", PATH) }

    assert_equal "invalid YAML in #{PATH} at line 1, column 11", error.message
  end

  def test_write_replaces_a_file_atomically_with_the_given_mode
    Dir.mktmpdir do |dir|
      path = File.join(dir, "master.key")
      File.write(path, "old", perm: 0o644)
      Credentials.write(path, "new\n", perm: 0o600)

      assert_equal ["new\n", 0o600], [File.read(path), File.stat(path).mode & 0o777]
      assert_equal ["master.key"], Dir.children(dir)
    end
  end

  def test_write_leaves_no_temporary_file_when_it_fails
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      Dir.mkdir(target)

      assert_raises(SystemCallError) { Credentials.write(target, "x", perm: 0o600) }
      assert_equal ["target"], Dir.children(dir)
    end
  end

end
