# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "shellwords"
require "tmpdir"
require "yaml"

# Temporary projects with encrypted credentials.
module CredentialsHelper

  SECRET = "sk-123-geheim"

  # A job that needs a secret and writes it reversed, so tests can check the
  # value without the secret itself appearing in the output.
  SECRET_JOB = <<~RUBY
    # frozen_string_literal: true

    Metacrunch.job do
      params do
        param :api_key, String, env: "CATALOG_API_KEY", credential: "catalog.api_key", required: true
        param :output, String, default: "-"
      end

      source [1, 2]
      map { params.api_key.reverse }
      sink Metacrunch::JsonLines::Writer.new(params.output)
    end
  RUBY

  # Yields the real path of a new temporary directory (macOS links /var to
  # /private/var, and the credentials code resolves links).
  def in_tmpdir
    Dir.mktmpdir("metacrunch-test") { |dir| yield File.realpath(dir) }
  end

  # Writes ROOT/.metacrunch/credentials[.ENV].yml.enc with data (a Hash or
  # YAML text) and, with key_file: true, the key file. Returns the key.
  def write_credentials(root, data, environment: nil, key: Metacrunch::Credentials::Key.generate, key_file: true)
    dir = File.join(root, ".metacrunch")
    FileUtils.mkdir_p(dir)
    text = data.is_a?(String) ? data : YAML.dump(data)
    content = Metacrunch::Credentials::Box.seal(text, key)
    File.write(File.join(dir, Metacrunch::Credentials.file_name(environment)), content)
    File.write(File.join(dir, Metacrunch::Credentials.key_name(environment)), "#{key.hex}\n") if key_file
    key
  end

  # Writes a file below root, with its directories, and returns its path.
  def write_file(root, relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def unseal(path, key) = Metacrunch::Credentials::Box.unseal(File.binread(path), key, path:)

  # The editor script: logs every call to calls.jsonl (path, modes, the
  # text it found), writes contents[n] on the n-th call (keeps the text if
  # there is none) and exits with the status in its directory.
  EDITOR_SCRIPT = <<~RUBY
    # frozen_string_literal: true

    require "json"

    path = ARGV.fetch(0)
    log = File.join(__dir__, "calls.jsonl")
    calls = File.exist?(log) ? File.readlines(log).size : 0
    File.open(log, "a") do |file|
      file.puts(JSON.generate("path" => path, "mode" => File.stat(path).mode & 0o777,
                              "dir_mode" => File.stat(File.dirname(path)).mode & 0o777, "before" => File.read(path)))
    end
    contents = JSON.parse(File.read(File.join(__dir__, "contents.json")))
    File.write(path, contents[calls]) if contents[calls]
    actions = JSON.parse(File.read(File.join(__dir__, "actions.json")))
    File.delete(path) if actions["delete"]
    Process.kill("INT", Process.ppid) if actions["interrupt_parent"]
    if actions["signal"]
      Process.kill(actions["signal"], Process.pid)
      sleep 1
    end
    exit Integer(File.read(File.join(__dir__, "status")))
  RUBY

  # An EDITOR command that writes contents[n] on its n-th call and ends with
  # status. Its files live in ROOT/editor. actions: delete: true removes
  # the file, interrupt_parent: true sends SIGINT to metacrunch, signal:
  # "TERM" ends the editor by that signal.
  def scripted_editor(root, *contents, status: 0, **actions)
    dir = File.join(root, "editor")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "editor.rb"), EDITOR_SCRIPT)
    File.write(File.join(dir, "contents.json"), JSON.generate(contents))
    File.write(File.join(dir, "actions.json"), JSON.generate(actions))
    File.write(File.join(dir, "status"), status.to_s)
    Shellwords.join([RbConfig.ruby, File.join(dir, "editor.rb")])
  end

  # The calls of the scripted editor below root.
  def editor_calls(root)
    log = File.join(root, "editor", "calls.jsonl")
    File.exist?(log) ? File.readlines(log).map { JSON.parse(it) } : []
  end

end
