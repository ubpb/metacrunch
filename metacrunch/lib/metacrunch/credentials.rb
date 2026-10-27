# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "yaml"

module Metacrunch
  # Encrypted credentials for job parameters: one file and one key per
  # environment in a .metacrunch/ directory (see docs/credentials.md).
  module Credentials

    DIRECTORY = ".metacrunch"
    KEY_VARIABLE = "METACRUNCH_MASTER_KEY"
    ENVIRONMENT_VARIABLE = "METACRUNCH_ENV"
    DIRECTORY_VARIABLE = "METACRUNCH_CREDENTIALS"
    ENVIRONMENT_NAME = /\A[a-z0-9_-]+\z/
    # The environment without -e: the files without an environment, the
    # default: section of a params file.
    DEFAULT_ENVIRONMENT = "default"
    RESERVED = "default is the environment without -e"

    # Reads every plain scalar as its text, so that credential values are
    # converted like command-line values (YAML 1.1 would make "no" false and
    # "0123" 83). The forms of null stay nil.
    class TextScanner < Psych::ScalarScanner

      NULL = ["", "~", "null", "Null", "NULL"].freeze

      def tokenize(string) = NULL.include?(string) ? nil : string

    end

    module_function

    def file_name(environment) = environment ? "credentials.#{environment}.yml.enc" : "credentials.yml.enc"

    def key_name(environment) = environment ? "master.#{environment}.key" : "master.key"

    # The environment from the option (-e), else METACRUNCH_ENV; nil for the
    # default environment, when neither is set. Empty values count as unset.
    # default names the environment without -e and is reserved.
    def environment(option, env) = environment_source(option, env)&.first

    # environment: of Job#run and Project#invoke: default is reserved there
    # as for -e, with a message for Ruby.
    def check_keyword!(environment)
      return unless environment == DEFAULT_ENVIRONMENT

      raise CredentialsError, %(environment: "default" is reserved: leave environment: out for the default environment)
    end

    # [name, "-e" or "METACRUNCH_ENV"] of the selected environment, or nil
    # for the default environment; checked as environment.
    def environment_source(option, env)
      name, source = present(option) ? [option, "-e"] : [present(env[ENVIRONMENT_VARIABLE]), ENVIRONMENT_VARIABLE]
      return if name.nil?

      from_variable = source == ENVIRONMENT_VARIABLE
      if name == DEFAULT_ENVIRONMENT
        raise CredentialsError, "#{RESERVED}; leave -e out" unless from_variable

        raise CredentialsError, "#{ENVIRONMENT_VARIABLE}=#{name}: #{RESERVED}; unset #{ENVIRONMENT_VARIABLE}"
      end
      return [name, source] if ENVIRONMENT_NAME.match?(name)

      raise CredentialsError,
            "invalid environment #{name.inspect}#{" (from #{ENVIRONMENT_VARIABLE})" if from_variable}: " \
            "use a-z, 0-9, _ and -"
    end

    def present(value) = (value unless value.nil? || value.empty?)

    # The store for a run: Location.for_job with the run's options.
    def store(job_file:, env:, logger: nil, environment: nil, directory: nil)
      Store.new(Location.for_job(job_file:, env:, environment:, directory:), logger:)
    end

    # The Hash in decrypted YAML (see parse_yaml).
    def load_yaml(text, path)
      data = parse_yaml(text, path, error: CredentialsError)
      return {} if data.nil?
      return data if data.is_a?(Hash)

      raise CredentialsError, "#{path} must contain a mapping at the top level"
    end

    # The data in YAML text, nil for none, with texts for all scalars
    # (TextScanner); also for params files. Anchors, aliases and merge keys
    # work; tags of Ruby classes do not. Errors are of class error, name the
    # position, never the content, and keep no cause, because Psych messages
    # can quote it.
    def parse_yaml(text, path, error:)
      document = Psych.parse(text) or return
      loader = Psych::ClassLoader::Restricted.new([], [])
      Psych::Visitors::ToRuby.new(TextScanner.new(loader), loader).accept(document)
    rescue Psych::DisallowedClass => e
      type = e.message[/unspecified class: (\S+)/, 1]
      raise error, "unsupported value in #{path}: #{type} (quote it)", cause: nil
    rescue Psych::SyntaxError => e
      raise error, "invalid YAML in #{path} at line #{e.line}, column #{e.column}", cause: nil
    rescue Psych::Exception
      raise error, "invalid YAML in #{path}", cause: nil
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
