# frozen_string_literal: true

require "test_helper"
require "open3"

class ExeCredentialsTest < Minitest::Test

  include CredentialsHelper

  ROOT = File.expand_path("../..", __dir__)
  OUTPUT = ("\"#{CredentialsHelper::SECRET.reverse}\"\n" * 2).freeze
  PIN_JOB = <<~RUBY
    # frozen_string_literal: true

    Metacrunch.job do
      params do
        param :pin, Integer, credential: "catalog.api_key", required: true
      end

      source [params.pin]
    end
  RUBY

  def test_edit_then_run_from_another_directory
    in_tmpdir do |root|
      project = File.join(root, "project")
      editor = scripted_editor(root, "catalog:\n  api_key: #{SECRET}\n")
      _out, edit_err, edit_status = metacrunch("credentials", "edit", env: {"EDITOR" => editor}, chdir: mkdir(project))
      stdout, stderr, status = metacrunch("run", write_file(project, "jobs/secret.rb", SECRET_JOB), chdir: root)

      assert_predicate edit_status, :success?, edit_err
      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_ctrl_c_while_the_editor_runs_reaches_only_the_editor
    in_tmpdir do |root|
      editor = scripted_editor(root, "a: 1\n", interrupt_parent: true)
      _stdout, stderr, status = metacrunch("credentials", "edit", env: {"EDITOR" => editor}, chdir: root)

      assert_equal 0, status.exitstatus, stderr
      assert_path_exists File.join(root, ".metacrunch", "credentials.yml.enc")
    end
  end

  def test_production_with_the_key_variable_and_no_key_file
    in_tmpdir do |root|
      key = write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production", key_file: false)
      env = {"METACRUNCH_ENV" => "production", "METACRUNCH_MASTER_KEY" => key.hex}
      stdout, stderr, status = metacrunch("run", job(root), env:, chdir: root)

      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_production_does_not_fall_back_to_the_file_without_environment
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}})
      _stdout, stderr, status = metacrunch("run", "-e", "production", job(root), chdir: root)

      assert_equal 2, status.exitstatus
      assert_includes stderr, "no credentials for environment production in #{root}/.metacrunch"
    end
  end

  def test_the_env_variable_overrides_the_credential
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}})
      stdout, _stderr, status = metacrunch("run", job(root), env: {"CATALOG_API_KEY" => "other"}, chdir: root)

      assert_equal [0, "\"rehto\"\n" * 2], [status.exitstatus, stdout]
    end
  end

  def test_values_from_env_need_neither_key_nor_file
    in_tmpdir do |root|
      stdout, stderr, status = metacrunch("run", job(root), env: {"CATALOG_API_KEY" => SECRET}, chdir: root)

      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_workers_get_the_secret
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}})
      stdout, stderr, status = metacrunch("run", "-w", "2", job(root), chdir: root)

      assert_equal [0, OUTPUT], [status.exitstatus, stdout], stderr
    end
  end

  def test_the_secret_appears_in_no_output
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}})
      pin = write_file(root, "jobs/pin.rb", PIN_JOB)
      wrong = {"METACRUNCH_MASTER_KEY" => Metacrunch::Credentials::Key.generate.hex}
      runs = [[["run", job(root), "--help"]], [["run", "-v", job(root)]], [["check", "-v", job(root)]],
              [["run", "-v", pin]], [["run", job(root)], wrong], [["run", job(root), "--api-key", SECRET]]]
      outputs = runs.map { |args, env| metacrunch(*args, env: env || {}, chdir: root).take(2).join }

      assert_empty outputs.grep(/#{SECRET}/)
      assert_includes outputs[3], "(hidden) is not an Integer"
    end
  end

  private

  def job(root) = write_file(root, "jobs/secret.rb", SECRET_JOB)

  def mkdir(path) = path.tap { FileUtils.mkdir_p(it) }

  # Runs exe/metacrunch in chdir. HOME is an empty directory and the
  # variables of the developer's shell that would change a run are unset.
  def metacrunch(*, chdir:, env: {})
    home = File.join(chdir, ".test-home")
    FileUtils.mkdir_p(home)
    clean = {"HOME" => home, "METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil,
             "METACRUNCH_MASTER_KEY" => nil, "CATALOG_API_KEY" => nil, "VISUAL" => nil, "EDITOR" => nil}
    Open3.capture3(clean.merge(env), RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"),
                   *, chdir:)
  end

end
