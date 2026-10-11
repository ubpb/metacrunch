# frozen_string_literal: true

require "shellwords"
require "tmpdir"

module Metacrunch
  module Credentials

    # An edit ended without saving: the editor failed, or invalid YAML was
    # not fixed. The CLI exits with 1.
    class EditAborted < Error; end

    # Lets the user edit plaintext with VISUAL or EDITOR. The plaintext
    # lives in a temporary directory of its own (mode 0700, the file 0600),
    # which is removed in any case.
    class Editor

      def initialize(env:, stdin:, stderr:)
        @env = env
        @stdin = stdin
        @stderr = stderr
      end

      # Returns the edited text. name: the file name the editor sees. The
      # block checks the text and raises CredentialsError if it is invalid;
      # on a terminal the user may then edit again.
      def edit(text, name:)
        command = editor_command
        Dir.mktmpdir("metacrunch-credentials") do |dir|
          path = File.join(dir, name)
          File.open(path, "w", 0o600) { it.write(text) }
          loop do
            run(command, path)
            edited = File.read(path)
            begin
              yield edited
              return edited
            rescue CredentialsError => e
              @stderr.puts("Error: #{e.message}")
              raise EditAborted, "nothing saved" unless again?
            end
          end
        end
      end

      private

      def editor_command
        value = Credentials.present(@env["VISUAL"]) || Credentials.present(@env["EDITOR"])
        raise CredentialsError, "set VISUAL or EDITOR to edit credentials" unless value

        Shellwords.split(value)
      end

      def run(command, path)
        started = system(*command, path)
        return if started

        reason = started.nil? ? "could not be started" : "exited with status #{Process.last_status.exitstatus}"
        raise EditAborted, "editor #{command.first} #{reason}; nothing saved"
      end

      def again?
        return false unless @stdin.tty?

        @stderr.print("Edit again? [Y/n] ")
        answer = @stdin.gets
        !answer.nil? && !answer.strip.downcase.start_with?("n")
      end

    end

  end
end
