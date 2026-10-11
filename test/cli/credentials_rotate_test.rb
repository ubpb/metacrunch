# frozen_string_literal: true

require "test_helper"

class CredentialsRotateTest < Minitest::Test

  include CliHelper
  include CredentialsHelper
  include Override

  Key = Metacrunch::Credentials::Key

  def test_rotate_encrypts_with_a_new_key_in_the_key_file
    in_tmpdir do |root|
      old_key = write_credentials(root, "a: 1\n")
      code, stdout, stderr = Dir.chdir(root) { cli("credentials", "rotate") }
      new_key = Key.parse(File.read(key_file(root)), source: "test")

      assert_equal [0, ""], [code, stdout], stderr
      assert_equal "a: 1\n", unseal(credentials_file(root), new_key)
      assert_raises(Metacrunch::CredentialsError) { unseal(credentials_file(root), old_key) }
    end
  end

  def test_rotate_leaves_only_the_two_files_with_their_modes
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      Dir.chdir(root) { cli("credentials", "rotate") }

      assert_equal ["credentials.yml.enc", "master.key"], Dir.children(File.join(root, ".metacrunch")).sort
      assert_equal [0o644, 0o600], [file_mode(credentials_file(root)), file_mode(key_file(root))]
    end
  end

  def test_with_the_key_variable_the_new_key_goes_to_stdout
    in_tmpdir do |root|
      old_key = write_credentials(root, "a: 1\n", key_file: false)
      env = {"METACRUNCH_MASTER_KEY" => old_key.hex}
      code, stdout, stderr = Dir.chdir(root) { cli("credentials", "rotate", env:) }

      assert_equal 0, code
      assert_equal "a: 1\n", unseal(credentials_file(root), Key.parse(stdout, source: "stdout"))
      assert_includes stderr, "Update METACRUNCH_MASTER_KEY wherever it is set"
    end
  end

  def test_with_the_key_variable_a_key_file_is_reported_as_stale
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      _code, _stdout, stderr = Dir.chdir(root) do
        cli("credentials", "rotate", env: {"METACRUNCH_MASTER_KEY" => key.hex})
      end

      assert_includes stderr, "Warning: .metacrunch/master.key still holds the old key; replace or remove it"
      assert_equal "#{key.hex}\n", File.read(key_file(root))
    end
  end

  def test_a_failure_before_the_renames_changes_nothing
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      before = snapshot(root)
      code = override(File, :rename, ->(*) { raise Errno::EACCES, "test" }) do
        Dir.chdir(root) { cli("credentials", "rotate").first }
      end

      assert_equal 1, code
      assert_equal before, snapshot(root)
    end
  end

  def test_when_the_second_rename_fails_the_new_key_waits_in_a_new_file
    in_tmpdir do |root|
      old_key = write_credentials(root, "a: 1\n")
      code = override(File, :rename, failing_second_rename) { Dir.chdir(root) { cli("credentials", "rotate").first } }
      pending = Key.parse(File.read("#{key_file(root)}.new"), source: "test")

      assert_equal 1, code
      assert_equal "a: 1\n", unseal(credentials_file(root), pending)
      assert_equal "#{old_key.hex}\n", File.read(key_file(root))
    end
  end

  def test_rotate_needs_the_current_key_and_the_file
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n", key_file: false)

      assert_equal 2, Dir.chdir(root) { cli("credentials", "rotate").first }
      assert_equal 2, Dir.chdir(root) { cli("credentials", "rotate", "-e", "production").first }
    end
  end

  private

  def credentials_file(root) = File.join(root, ".metacrunch", "credentials.yml.enc")

  def key_file(root) = File.join(root, ".metacrunch", "master.key")

  def file_mode(path) = File.stat(path).mode & 0o777

  def snapshot(root)
    dir = File.join(root, ".metacrunch")
    Dir.children(dir).sort.to_h { [it, File.binread(File.join(dir, it))] }
  end

  def failing_second_rename
    rename = File.method(:rename)
    calls = 0
    lambda do |from, to|
      calls += 1
      raise Errno::EACCES, "test" if calls == 2

      rename.call(from, to)
    end
  end

end
