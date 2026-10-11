# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch credentials edit|show|rotate: the encrypted credentials of
    # the project in the working directory (see Credentials::Location).
    class CredentialsCommand < Command

      NAME = "credentials"
      SUMMARY = "Edit, show or rotate encrypted credentials"
      USAGE = "credentials edit|show|rotate [-e ENV] [--credentials DIR]"
      SUBCOMMANDS = ["edit", "show", "rotate"].freeze

      private

      def define_options(parser)
        credentials_options(parser, "Credentials directory (default: METACRUNCH_CREDENTIALS,",
                            "then .metacrunch/ above the working directory)")
      end

      # Options may stand before or after the subcommand.
      def parse(parser, argv) = parser.permute!(argv)

      def execute(argv)
        subcommand = argv.shift
        raise UsageError, "no subcommand given (edit, show or rotate)" unless subcommand
        raise UsageError, "unknown subcommand #{subcommand}" unless SUBCOMMANDS.include?(subcommand)
        raise UsageError, "unexpected arguments: #{argv.join(" ")}" if argv.any?

        location = Credentials::Location.for_command(cwd: Dir.pwd, env: @env, environment: @environment,
                                                     directory: @credentials)
        case subcommand
        when "show" then show_credentials(location)
        end
      end

      def show_credentials(location)
        file = existing_file(location)
        @stderr.puts("Showing #{display(file)}")
        @stdout.puts(unseal(location))
        EXIT_CODES[:ok]
      end

      # The credentials file of location; raises if it or its directory is
      # missing.
      def existing_file(location)
        unless location.exist?
          raise CredentialsError, "credentials directory not found: #{location.directory}" if location.explicit?

          raise CredentialsError, "no #{Credentials::DIRECTORY}/ found above #{Dir.pwd}; use --credentials"
        end
        file = location.file
        raise CredentialsError, "no credentials file #{file}" unless File.file?(file)

        file
      end

      def unseal(location, key = location.key!)
        Credentials::Box.unseal(File.binread(location.file), key, path: location.file)
      end

      # path relative to the working directory if it is below it.
      def display(path)
        cwd = "#{Dir.pwd}/"
        path.start_with?(cwd) ? path.delete_prefix(cwd) : path
      end

    end
  end
end
