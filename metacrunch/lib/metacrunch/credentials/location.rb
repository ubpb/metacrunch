# frozen_string_literal: true

module Metacrunch
  module Credentials
    # Where the credentials of one environment are: a directory, the file
    # and the key file in it. A run searches from its job file (for_job),
    # the credentials command from the working directory (for_command).
    class Location

      attr_reader :directory, :environment, :searched

      # --credentials DIR (directory:), else METACRUNCH_CREDENTIALS, else the
      # nearest .metacrunch/ at or above the job file (links resolved), else
      # ~/.metacrunch/. directory is nil if there is none.
      def self.for_job(job_file:, env:, environment: nil, directory: nil)
        environment = Credentials.environment(environment, env)
        explicit = explicit_directory(directory, env)
        return new(expand(explicit), environment:, env:, explicit: true) if explicit

        personal = personal_directory(env)
        found = job_file && upward(File.dirname(File.realpath(job_file)))
        found ||= personal if personal && File.directory?(personal)
        searched = [("no #{DIRECTORY}/ above #{job_file}" if job_file), "no ~/#{DIRECTORY}/"].compact.join(", ")
        new(found, environment:, env:, searched:)
      end

      # Like for_job, but from the working directory, and ~/.metacrunch/
      # only when it is given. Without a .metacrunch/ above cwd the
      # directory is cwd/.metacrunch, which edit creates.
      def self.for_command(cwd:, env:, environment: nil, directory: nil)
        environment = Credentials.environment(environment, env)
        explicit = explicit_directory(directory, env)
        return new(expand(explicit, cwd), environment:, env:, explicit: true) if explicit

        found = upward(File.realpath(cwd), skip: personal_directory(env))
        new(found || File.join(cwd, DIRECTORY), environment:, env:, searched: "no #{DIRECTORY}/ above #{cwd}")
      end

      def self.explicit_directory(option, env)
        Credentials.present(option) || Credentials.present(env[DIRECTORY_VARIABLE])
      end

      # "~nosuchuser/x" cannot be expanded.
      def self.expand(directory, base = nil)
        File.expand_path(directory, base)
      rescue ArgumentError
        raise CredentialsError, "invalid credentials directory #{directory}", cause: nil
      end

      def self.personal_directory(env)
        home = Credentials.present(env["HOME"])
        home && File.join(home, DIRECTORY)
      end

      # The nearest DIRECTORY at or above start, except skip. File.identical?
      # also recognizes skip through links (a ~/.metacrunch from dotfiles).
      def self.upward(start, skip: nil)
        dir = start
        loop do
          candidate = File.join(dir, DIRECTORY)
          return candidate if File.directory?(candidate) && !(skip && File.identical?(candidate, skip))

          parent = File.dirname(dir)
          return if parent == dir

          dir = parent
        end
      end

      private_class_method :explicit_directory, :expand, :personal_directory, :upward

      def initialize(directory, environment:, env:, explicit: false, searched: nil)
        @directory = directory
        @environment = environment
        @env = env
        @explicit = explicit
        @searched = searched
      end

      def explicit? = @explicit

      # Without @env, which may hold METACRUNCH_MASTER_KEY.
      def inspect = "#<#{self.class.name} #{directory || "without directory"} environment=#{environment.inspect}>"

      def exist? = !directory.nil? && File.directory?(directory)

      def file = directory && File.join(directory, Credentials.file_name(environment))

      def key_file = directory && File.join(directory, Credentials.key_name(environment))

      # METACRUNCH_MASTER_KEY, else the key file; nil if there is neither.
      def key
        value = Credentials.present(@env[KEY_VARIABLE])
        return Key.parse(value, source: KEY_VARIABLE) if value
        return unless key_file && File.file?(key_file)

        Key.parse(Credentials.read(key_file), source: key_file)
      end

      def key!
        key || raise(CredentialsError, "no key for #{file}: set #{KEY_VARIABLE} or create #{key_file}")
      end

    end
  end
end
