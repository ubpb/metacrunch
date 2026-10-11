# frozen_string_literal: true

require "fileutils"

module Metacrunch
  class Cli
    # metacrunch credentials edit|show|rotate: the encrypted credentials of
    # the project in the working directory (see Credentials::Location).
    class CredentialsCommand < Command

      NAME = "credentials"
      SUMMARY = "Edit, show or rotate encrypted credentials"
      USAGE = "credentials edit|show|rotate [-e ENV] [--credentials DIR]"
      SUBCOMMANDS = ["edit", "show", "rotate"].freeze
      GITIGNORE = "master*.key\n"
      TEMPLATE = <<~YAML
        # Credentials for metacrunch jobs%<environment>s. They are encrypted when you save.
        # A parameter reads a value with credential: "catalog.api_key":
        #
        # catalog:
        #   api_key: secret
        #
        # Quote values that YAML reads as numbers or booleans: "0123", "yes", "on".
      YAML

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
        when "edit" then edit_credentials(location)
        when "show" then show_credentials(location)
        when "rotate" then rotate_credentials(location)
        end
      rescue Credentials::EditAborted => e
        @stderr.puts("Error: #{e.message}")
        EXIT_CODES[:aborted]
      end

      def show_credentials(location)
        file = existing_file(location)
        @stderr.puts("Showing #{display(file)}")
        @stdout.puts(unseal(location))
        EXIT_CODES[:ok]
      end

      def edit_credentials(location)
        file = location.file
        existing = File.file?(file)
        key = existing ? location.key! : location.key
        text = existing ? unseal(location, key) : template(location.environment)
        @stderr.puts("Editing #{display(file)}")
        edited = editor.edit(text, name: File.basename(file, ".enc")) { Credentials.load_yaml(it, file) }
        return no_changes if existing && edited == text

        prepare(location.directory) unless existing
        key ||= create_key(location)
        Credentials.write(file, Credentials::Box.seal(edited, key), perm: 0o644)
        @stderr.puts("Saved #{display(file)}")
        EXIT_CODES[:ok]
      end

      def template(environment)
        format(TEMPLATE, environment: environment ? " (environment: #{environment})" : "")
      end

      def editor = Credentials::Editor.new(env: @env, stdin: @stdin, stderr: @stderr)

      def no_changes
        @stderr.puts("No changes. If your editor returns at once, make it wait, e.g. EDITOR=\"code --wait\".")
        EXIT_CODES[:ok]
      end

      # A new directory gets a .gitignore that keeps the keys out of git.
      def prepare(directory)
        FileUtils.mkdir_p(directory)
        gitignore = File.join(directory, ".gitignore")
        File.write(gitignore, GITIGNORE) unless File.exist?(gitignore)
      end

      def create_key(location)
        key = Credentials::Key.generate
        Credentials.write(location.key_file, "#{key.hex}\n", perm: 0o600)
        @stderr.puts("Created #{display(location.key_file)}: keep it safe; it is not committed")
        key
      end

      def rotate_credentials(location)
        file = existing_file(location)
        old_key = location.key!
        plaintext = unseal(location, old_key)
        key = Credentials::Key.generate
        @stderr.puts("Rotating #{display(file)}")
        if old_key.source == Credentials::KEY_VARIABLE
          rotate_variable_key(location, plaintext, key)
        else
          rotate_key_file(location, plaintext, key)
        end
        EXIT_CODES[:ok]
      end

      # The new key goes to stdout once; whoever set the variable updates it.
      # It is printed (and flushed) before the file changes, so a closed
      # stdout leaves the file with the old key.
      def rotate_variable_key(location, plaintext, key)
        sealed = Credentials::Box.seal(plaintext, key)
        @stdout.puts(key.hex)
        @stdout.flush
        begin
          Credentials.write(location.file, sealed, perm: 0o644)
        rescue SystemCallError => e
          raise CredentialsError, "cannot write #{location.file} (#{e.class.name}): the printed key is void; " \
                                  "the old key still works"
        end
        @stderr.puts("Update #{Credentials::KEY_VARIABLE} wherever it is set; the old key no longer works")
        return unless File.file?(location.key_file)

        @stderr.puts("Warning: #{display(location.key_file)} still holds the old key; replace or remove it")
      end

      # Both new files are written before either is renamed, so an error
      # until then changes nothing. If the second rename fails,
      # KEY_FILE.new holds the key of the new credentials file.
      def rotate_key_file(location, plaintext, key)
        sealed = "#{location.file}.#{Process.pid}.tmp"
        pending = "#{location.key_file}.new"
        begin
          File.open(sealed, "w", 0o644) { it.write(Credentials::Box.seal(plaintext, key)) }
          File.open(pending, "w", 0o600) { it.write("#{key.hex}\n") }
          File.chmod(0o600, pending)
          File.rename(sealed, location.file)
        rescue StandardError
          FileUtils.rm_f([sealed, pending])
          raise
        end
        File.rename(pending, location.key_file)
        @stderr.puts("New key in #{display(location.key_file)}")
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
