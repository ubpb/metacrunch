# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "yaml"

module Metacrunch
  # Encrypted credentials for job parameters: one file and one key per
  # environment in a .metacrunch/ directory (see the Readme, "Credentials").
  module Credentials

    DIRECTORY = ".metacrunch"
    KEY_VARIABLE = "METACRUNCH_MASTER_KEY"
    ENVIRONMENT_VARIABLE = "METACRUNCH_ENV"
    DIRECTORY_VARIABLE = "METACRUNCH_CREDENTIALS"
    ENVIRONMENT_NAME = /\A[a-z0-9_-]+\z/

    module_function

    def file_name(environment) = environment ? "credentials.#{environment}.yml.enc" : "credentials.yml.enc"

    def key_name(environment) = environment ? "master.#{environment}.key" : "master.key"

    # The environment from the option (-e), else METACRUNCH_ENV; nil if
    # neither is set. Empty values count as unset.
    def environment(option, env)
      name = present(option) || present(env[ENVIRONMENT_VARIABLE])
      return if name.nil?
      return name if ENVIRONMENT_NAME.match?(name)

      raise CredentialsError, "invalid environment #{name.inspect}: use a-z, 0-9, _ and -"
    end

    def present(value) = (value unless value.nil? || value.empty?)

    # The store for a run: Location.for_job with the run's options.
    def store(job_file:, env:, logger: nil, environment: nil, directory: nil)
      Store.new(Location.for_job(job_file:, env:, environment:, directory:), logger:)
    end

    # The Hash in decrypted YAML. Errors name the position, never the
    # content, and keep no cause, because Psych messages can quote it.
    def load_yaml(text, path)
      data = YAML.safe_load(text, aliases: true)
      return {} if data.nil?
      return data if data.is_a?(Hash)

      raise CredentialsError, "#{path} must contain a mapping at the top level"
    rescue Psych::DisallowedClass => e
      type = e.message[/unspecified class: (\S+)/, 1]
      raise CredentialsError, "unsupported value in #{path}: #{type} (quote it)", cause: nil
    rescue Psych::SyntaxError => e
      raise CredentialsError, "invalid YAML in #{path} at line #{e.line}, column #{e.column}", cause: nil
    rescue Psych::Exception
      raise CredentialsError, "invalid YAML in #{path}", cause: nil
    end

    # The bytes of a credentials or key file. Errors name the file and the
    # reason ("Permission denied"), as a CredentialsError.
    def read(path)
      File.binread(path)
    rescue SystemCallError => e
      raise CredentialsError, "cannot read #{path}: #{e.message.split(" @ ").first}", cause: nil
    end

    # Writes content to path atomically: to a new temporary file next to it
    # (a random name), then renamed over path.
    def write(path, content, perm:)
      temp = "#{path}.#{SecureRandom.hex(8)}.tmp"
      create(temp, content, perm:)
      renamed = false
      begin
        File.rename(temp, path)
        renamed = true
      ensure
        FileUtils.rm_f(temp) unless renamed
      end
      nil
    end

    # Creates path with content and exactly mode perm (whatever the umask).
    # Raises Errno::EEXIST if path exists, so it never writes through a
    # link planted there; removes what it created if it fails later.
    def create(path, content, perm:)
      opened = false
      done = false
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, perm) do |file|
        opened = true
        file.write(content)
      end
      File.chmod(perm, path)
      done = true
      nil
    ensure
      FileUtils.rm_f(path) if opened && !done
    end

  end
end
