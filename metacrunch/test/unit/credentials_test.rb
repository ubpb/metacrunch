# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CredentialsTest < Minitest::Test

  Credentials = Metacrunch::Credentials
  PATH = "/p/.metacrunch/credentials.yml.enc"

  YAML_ERRORS = {
    "a: [\n" => "invalid YAML in #{PATH} at line 2, column 1",
    "- a\n" => "#{PATH} must contain a mapping at the top level",
    "x: !ruby/object:Object {}\n" => "unsupported value in #{PATH}: Object (quote it)",
    "x: !ruby/encoding UTF-8\n" => "unsupported value in #{PATH}: Encoding (quote it)",
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

  def test_reads_every_scalar_as_its_text
    text = "n: 1\npin: 0123\nok: true\nno: off\nd: 2026-10-11\ns: :sym\nl: [a, 2]\nq: \"x\"\n"

    assert_equal({"n" => "1", "pin" => "0123", "ok" => "true", "no" => "off", "d" => "2026-10-11", "s" => ":sym",
                  "l" => ["a", "2"], "q" => "x"}, Credentials.load_yaml(text, PATH))
  end

  def test_the_forms_of_null_stay_nil
    data = Credentials.load_yaml("a:\nb: ~\nc: null\nd: \"null\"\n", PATH)

    assert_equal({"a" => nil, "b" => nil, "c" => nil, "d" => "null"}, data)
  end

  def test_anchors_aliases_and_merge_keys_work
    data = Credentials.load_yaml("x: &k v\ny: *k\nbase: &b {a: 1}\nm:\n  <<: *b\n  c: 2\n", PATH)

    assert_equal({"x" => "v", "y" => "v", "base" => {"a" => "1"}, "m" => {"a" => "1", "c" => "2"}}, data)
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

  def test_create_never_writes_through_an_existing_path
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      File.write(target, "keep")
      File.symlink(target, File.join(dir, "master.key"))

      assert_raises(Errno::EEXIST) { Credentials.create(File.join(dir, "master.key"), "new", perm: 0o600) }
      assert_equal "keep", File.read(target)
    end
  end

  def test_create_sets_the_mode_whatever_the_umask
    Dir.mktmpdir do |dir|
      path = File.join(dir, "credentials.yml.enc")
      with_umask(0o077) { Credentials.create(path, "x", perm: 0o644) }

      assert_equal 0o644, File.stat(path).mode & 0o777
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

  private

  def with_umask(mask)
    previous = File.umask(mask)
    yield
  ensure
    File.umask(previous)
  end

end
