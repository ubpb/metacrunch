# frozen_string_literal: true

require "test_helper"

class CredentialsEditTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  Key = Metacrunch::Credentials::Key

  def test_creates_key_gitignore_and_credentials
    in_tmpdir do |root|
      code, _stdout, stderr = edit(root, scripted_editor(root, "catalog:\n  api_key: pässwörd\n"))
      dir = File.join(root, ".metacrunch")
      key = Key.parse(File.read(File.join(dir, "master.key")), source: "test")

      assert_equal 0, code, stderr
      assert_equal "catalog:\n  api_key: pässwörd\n", unseal(File.join(dir, "credentials.yml.enc"), key)
      assert_equal ["master*.key*\n", 0o600],
                   [File.read(File.join(dir, ".gitignore")), File.stat(File.join(dir, "master.key")).mode & 0o777]
    end
  end

  def test_the_gitignore_keeps_keys_and_their_leftovers_out_of_git
    in_tmpdir do |root|
      system("git", "-C", root, "init", "-q", exception: true)
      edit(root, scripted_editor(root, "a: 1\n"))
      paths = [".metacrunch/master.key", ".metacrunch/master.production.key.new", ".metacrunch/master.key.123.tmp"]
      ignored = paths.select { system("git", "-C", root, "check-ignore", "-q", it) }

      assert_equal paths, ignored
      refute system("git", "-C", root, "check-ignore", "-q", ".metacrunch/credentials.yml.enc")
    end
  end

  def test_names_the_new_key_and_the_saved_file
    in_tmpdir do |root|
      _code, _stdout, stderr = edit(root, scripted_editor(root, "a: 1\n"))

      assert_equal "Editing .metacrunch/credentials.yml.enc\nCreated .metacrunch/master.key: keep it safe; " \
                   "it is not committed\nSaved .metacrunch/credentials.yml.enc\n", stderr
    end
  end

  def test_a_new_file_starts_with_a_template_that_names_the_environment
    in_tmpdir do |root|
      edit(root, scripted_editor(root), "-e", "production")
      template = editor_calls(root).first["before"]

      assert_includes template, "(environment: production)"
      assert_includes template, "credential: \"catalog.api_key\""
      assert_path_exists File.join(root, ".metacrunch", "credentials.production.yml.enc")
    end
  end

  def test_an_existing_file_is_decrypted_for_the_editor
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: 2\n"))

      assert_equal 0, code
      assert_equal "a: 1\n", editor_calls(root).first["before"]
      assert_equal "a: 2\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_with_the_key_variable_no_key_file_is_written
    in_tmpdir do |root|
      key = Key.generate
      code, = edit(root, scripted_editor(root, "a: 1\n"), env: {"METACRUNCH_MASTER_KEY" => key.hex})

      assert_equal 0, code
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
      refute_path_exists File.join(root, ".metacrunch", "master.key")
    end
  end

  def test_the_plaintext_is_private_and_removed_afterwards
    in_tmpdir do |root|
      edit(root, scripted_editor(root, "a: 1\n"), "-e", "production")
      call = editor_calls(root).first

      assert_equal [0o600, 0o700], [call["mode"], call["dir_mode"]]
      assert_equal "credentials.production.yml", File.basename(call["path"])
      refute_path_exists File.dirname(call["path"])
    end
  end

  def test_a_failing_editor_saves_nothing
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, _stdout, stderr = edit(root, scripted_editor(root, "a: 2\n", status: 3))

      assert_equal 1, code
      assert_includes stderr, "exited with status 3; nothing saved"
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_the_plaintext_is_removed_when_the_editor_fails
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      edit(root, scripted_editor(root, "a: 2\n", status: 3))

      refute_path_exists File.dirname(editor_calls(root).first["path"])
    end
  end

  def test_unchanged_content_writes_nothing_and_says_how_to_make_an_editor_wait
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      file = File.join(root, ".metacrunch", "credentials.yml.enc")
      before = File.binread(file)
      code, _stdout, stderr = edit(root, scripted_editor(root))

      assert_equal 0, code
      assert_includes stderr, "No changes. If your editor returns at once, make it wait, e.g. EDITOR=\"code --wait\"."
      assert_equal before, File.binread(file)
    end
  end

  def test_an_unchanged_template_is_saved_with_the_hint_to_make_the_editor_wait
    in_tmpdir do |root|
      code, _stdout, stderr = edit(root, scripted_editor(root))

      assert_equal 0, code
      assert_includes stderr, "Saved .metacrunch/credentials.yml.enc\nThe file still holds the template. If your " \
                              "editor returns at once, make it wait, e.g. EDITOR=\"code --wait\"."
    end
  end

  def test_the_hint_names_visual_when_visual_is_set
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      _code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "edit", env: {"VISUAL" => scripted_editor(root)}) }

      assert_includes stderr, "make it wait, e.g. VISUAL=\"code --wait\"."
    end
  end

  def test_unchanged_non_ascii_text_is_not_rewritten_under_a_non_utf8_locale
    in_tmpdir do |root|
      write_credentials(root, "name: Müller\n")
      file = File.join(root, ".metacrunch", "credentials.yml.enc")
      before = File.binread(file)
      code, _stdout, stderr = with_default_external(Encoding::US_ASCII) { edit(root, scripted_editor(root)) }

      assert_equal 0, code
      assert_includes stderr, "No changes."
      assert_equal before, File.binread(file)
    end
  end

  def test_an_editor_killed_by_a_signal_saves_nothing
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, _stdout, stderr = edit(root, scripted_editor(root, "a: 2\n", signal: "TERM"))

      assert_equal 1, code
      assert_match(/editor \S+ was killed by SIGTERM; nothing saved/, stderr)
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_an_editor_ended_by_ctrl_c_ends_edit_like_ctrl_c
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: 2\n", signal: "INT"))

      assert_equal 130, code
      refute_path_exists File.dirname(editor_calls(root).first["path"])
    end
  end

  def test_an_editor_that_removes_the_file_saves_nothing
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      code, _stdout, stderr = edit(root, scripted_editor(root, delete: true))

      assert_equal 1, code
      assert_includes stderr, "the editor removed credentials.yml; nothing saved"
    end
  end

  def test_an_editor_that_cannot_be_started_saves_nothing
    in_tmpdir do |root|
      code, _stdout, stderr = edit(root, "/nonexistent/editor")

      assert_equal 1, code
      assert_includes stderr, "editor /nonexistent/editor could not be started; nothing saved"
    end
  end

  def test_invalid_yaml_without_a_terminal_saves_nothing
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, _stdout, stderr = edit(root, scripted_editor(root, "a: [\n"))

      assert_equal 1, code
      assert_includes stderr, "invalid YAML in #{root}/.metacrunch/credentials.yml.enc at line 2, column 1"
      assert_equal "a: 1\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_invalid_yaml_on_a_terminal_can_be_edited_again
    in_tmpdir do |root|
      key = write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: [\n", "a: 2\n"), stdin: TerminalInput.new("\n"))

      assert_equal 0, code
      assert_equal(["a: 1\n", "a: [\n"], editor_calls(root).map { it["before"] })
      assert_equal "a: 2\n", unseal(File.join(root, ".metacrunch", "credentials.yml.enc"), key)
    end
  end

  def test_answering_no_saves_nothing
    in_tmpdir do |root|
      write_credentials(root, "a: 1\n")
      code, = edit(root, scripted_editor(root, "a: [\n", "a: 2\n"), stdin: TerminalInput.new("n\n"))

      assert_equal 1, code
      assert_equal 1, editor_calls(root).size
    end
  end

  def test_visual_wins_over_editor
    in_tmpdir do |root|
      failing = Shellwords.join([RbConfig.ruby, "-e", "exit 1"])
      env = {"VISUAL" => scripted_editor(root, "a: 1\n"), "EDITOR" => failing}

      assert_equal 0, Dir.chdir(root) { cli("credentials", "edit", env:) }.first
    end
  end

  def test_without_an_editor_edit_fails
    in_tmpdir do |root|
      code, _stdout, stderr = Dir.chdir(root) { cli("credentials", "edit") }

      assert_equal 2, code
      assert_includes stderr, "set VISUAL or EDITOR to edit credentials"
    end
  end

  def test_creates_the_directory_in_the_working_directory_not_in_home
    in_tmpdir do |home|
      FileUtils.mkdir_p([File.join(home, ".metacrunch"), File.join(home, "new")])
      env = {"EDITOR" => scripted_editor(home, "a: 1\n"), "HOME" => home}
      Dir.chdir(File.join(home, "new")) { cli("credentials", "edit", env:) }

      assert_path_exists File.join(home, "new", ".metacrunch", "credentials.yml.enc")
      assert_empty Dir.children(File.join(home, ".metacrunch"))
    end
  end

  private

  # Runs the block as under LANG=C, where File.read gives US-ASCII.
  def with_default_external(encoding)
    verbose = $VERBOSE
    $VERBOSE = nil
    previous = Encoding.default_external
    Encoding.default_external = encoding
    yield
  ensure
    Encoding.default_external = previous
    $VERBOSE = verbose
  end

  def edit(root, editor, *options, env: {}, stdin: "")
    Dir.chdir(root) { cli("credentials", "edit", *options, env: env.merge("EDITOR" => editor), stdin:) }
  end

end
