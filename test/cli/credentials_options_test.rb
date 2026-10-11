# frozen_string_literal: true

require "test_helper"

class CredentialsOptionsTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  def test_run_gets_the_value_of_the_environment_given_by_option
    in_tmpdir do |root|
      job_file = project(root, environment: "production")
      code, stdout, stderr = cli("run", "-e", "production", job_file)

      assert_equal [0, "\"#{SECRET.reverse}\"\n" * 2], [code, stdout], stderr
      refute_includes stderr, SECRET
    end
  end

  def test_the_credentials_option_names_the_directory
    in_tmpdir do |root|
      write_credentials(File.join(root, "vault"), {"catalog" => {"api_key" => SECRET}})
      job_file = write_file(root, "jobs/secret.rb", SECRET_JOB)
      code, stdout, = cli("run", "--credentials", File.join(root, "vault", ".metacrunch"), job_file)

      assert_equal [0, "\"#{SECRET.reverse}\"\n" * 2], [code, stdout]
    end
  end

  def test_an_invalid_environment_name_is_a_usage_error
    in_tmpdir do |root|
      code, _stdout, stderr = cli("run", "-e", "Production", project(root))

      assert_equal 2, code
      assert_includes stderr, "invalid environment \"Production\""
    end
  end

  def test_a_wrong_key_is_a_usage_error_that_names_the_file
    in_tmpdir do |root|
      env = {"METACRUNCH_MASTER_KEY" => Metacrunch::Credentials::Key.generate.hex}
      code, _stdout, stderr = cli("run", project(root), env:)

      assert_equal 2, code
      assert_includes stderr, "cannot decrypt #{root}/.metacrunch/credentials.yml.enc: wrong key or modified file " \
                              "(key from METACRUNCH_MASTER_KEY)"
    end
  end

  def test_check_verifies_key_and_file
    in_tmpdir do |root|
      job_file = project(root)
      env = {"METACRUNCH_MASTER_KEY" => Metacrunch::Credentials::Key.generate.hex}

      assert_equal 0, cli("check", job_file).first
      assert_equal 2, cli("check", job_file, env:).first
    end
  end

  def test_verbose_logs_the_decrypted_file
    in_tmpdir do |root|
      _code, _stdout, stderr = cli("run", "-v", project(root))

      assert_includes stderr, "credentials: #{root}/.metacrunch/credentials.yml.enc"
      refute_includes stderr, SECRET
    end
  end

  def test_trace_gets_the_value
    in_tmpdir do |root|
      code, stdout, = cli("trace", "-n", "1", project(root))

      assert_equal 0, code
      assert_includes stdout, SECRET.reverse
    end
  end

  def test_run_help_lists_the_credentials_options
    stdout = cli("run", "--help")[1]

    assert_match(/-e, --environment NAME/, stdout)
    assert_match(/--credentials DIR/, stdout)
  end

  private

  # A project with credentials and the secret job; returns the job file.
  def project(root, environment: nil)
    write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment:)
    write_file(root, "jobs/secret.rb", SECRET_JOB)
  end

end
