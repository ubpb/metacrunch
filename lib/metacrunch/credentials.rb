# frozen_string_literal: true

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
    # content, because Psych messages can quote it.
    def load_yaml(text, path)
      data = YAML.safe_load(text, aliases: true)
      return {} if data.nil?
      return data if data.is_a?(Hash)

      raise CredentialsError, "#{path} must contain a mapping at the top level"
    rescue Psych::DisallowedClass => e
      raise CredentialsError, "unsupported value in #{path}: #{e.message[/unspecified class: (\S+)/, 1]} (quote it)"
    rescue Psych::SyntaxError => e
      raise CredentialsError, "invalid YAML in #{path} at line #{e.line}, column #{e.column}"
    rescue Psych::Exception
      raise CredentialsError, "invalid YAML in #{path}"
    end

    # Writes content to path atomically: to a temporary file next to it,
    # with mode perm, then renamed over path.
    def write(path, content, perm:)
      temp = "#{path}.#{Process.pid}.tmp"
      File.open(temp, "w", perm) { it.write(content) }
      File.chmod(perm, temp)
      File.rename(temp, path)
      nil
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end

  end
end
