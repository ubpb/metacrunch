# frozen_string_literal: true

require "fileutils"
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
        param :api_key, String, env: "FIS_API_KEY", credential: "fis.api_key", required: true
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

end
