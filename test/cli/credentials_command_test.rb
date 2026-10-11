# frozen_string_literal: true

require "test_helper"

class CredentialsCommandTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  def test_show_prints_the_plaintext_and_names_the_file
    in_tmpdir do |root|
      write_credentials(root, "fis:\n  api_key: geheim\n")
      code, stdout, stderr = Dir.chdir(root) { cli("credentials", "show") }

      assert_equal [0, "fis:\n  api_key: geheim\n"], [code, stdout]
      assert_equal "Showing .metacrunch/credentials.yml.enc\n", stderr
    end
  end

  def test_options_may_stand_before_or_after_the_subcommand
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n", environment: "production")
      after = Dir.chdir(root) { cli("credentials", "show", "-e", "production") }
      before = Dir.chdir(root) { cli("credentials", "-e", "production", "show") }

      assert_equal [0, "a: 1\n"], after.take(2)
      assert_equal after, before
    end
  end

  def test_show_searches_above_the_working_directory
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      FileUtils.mkdir_p(File.join(root, "jobs"))
      code, stdout, stderr = Dir.chdir(File.join(root, "jobs")) { cli("credentials", "show") }

      assert_equal [0, "a: 1\n"], [code, stdout]
      assert_equal "Showing #{root}/.metacrunch/credentials.yml.enc\n", stderr
    end
  end

  def test_show_without_a_directory_fails
    in_tmpdir do |root|
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show") }

      assert_equal 2, code
      assert_includes stderr, "no .metacrunch/ found above #{root}; use --credentials"
    end
  end

  def test_show_without_the_file_fails
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show", "-e", "production") }

      assert_equal 2, code
      assert_includes stderr, "no credentials file #{root}/.metacrunch/credentials.production.yml.enc"
    end
  end

  def test_show_with_a_missing_given_directory_fails
    in_tmpdir do |root|
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show", "--credentials", "vault") }

      assert_equal 2, code
      assert_includes stderr, "credentials directory not found: #{root}/vault"
    end
  end

  def test_show_of_an_unreadable_file_is_a_usage_error
    skip "root reads every file" if Process.euid.zero?
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      File.chmod(0o000, File.join(root, ".metacrunch", "credentials.yml.enc"))
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "show") }

      assert_equal 2, code
      assert_includes stderr, "Error: cannot read #{root}/.metacrunch/credentials.yml.enc: Permission denied"
    end
  end

  def test_missing_unknown_and_extra_subcommands_are_usage_errors
    assert_equal [2, 2, 2], [cli("credentials").first, cli("credentials", "list").first,
                             cli("credentials", "show", "extra").first]
    assert_includes cli("credentials", "list")[2], "unknown subcommand list"
  end

  def test_the_usage_lists_the_command
    assert_match(/^  credentials +Edit, show or rotate encrypted credentials$/, cli("--help")[1])
  end

end
