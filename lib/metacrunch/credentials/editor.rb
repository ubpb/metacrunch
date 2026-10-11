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

      EDITOR_VARIABLES = ["VISUAL", "EDITOR"].freeze
      # Like git, metacrunch ignores these while the editor runs, so Ctrl-C
      # reaches only the editor.
      IGNORED_SIGNALS = ["INT", "QUIT"].select { Signal.list.key?(it) }.freeze

      # The variable that names the editor (VISUAL before EDITOR), or nil.
      attr_reader :variable

      def initialize(env:, stdin:, stderr:)
        @env = env
        @stdin = stdin
        @stderr = stderr
        @variable = EDITOR_VARIABLES.find { Credentials.present(env[it]) }
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
            edited = read(path, name)
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
        raise CredentialsError, "set VISUAL or EDITOR to edit credentials" unless variable

        Shellwords.split(@env[variable])
      end

      # An editor ended by SIGINT ends the edit like Ctrl-C (exit 130).
      def run(command, path)
        status = wait_for(spawn(command, path))
        return if status.success?
        raise Interrupt if status.termsig == Signal.list["INT"]

        reason = if status.signaled?
          "was killed by SIG#{Signal.signame(status.termsig)}"
        else
          "exited with status #{status.exitstatus}"
        end
        raise EditAborted, "editor #{command.first} #{reason}; nothing saved"
      end

      def spawn(command, path)
        Process.spawn(*command, path)
      rescue SystemCallError
        raise EditAborted, "editor #{command.first} could not be started; nothing saved"
      end

      def wait_for(pid)
        previous = IGNORED_SIGNALS.to_h { [it, trap(it, "IGNORE")] }
        Process.wait2(pid).last
      ensure
        previous&.each { |signal, handler| trap(signal, handler) }
      end

      # The editor saves UTF-8, whatever the locale says.
      def read(path, name)
        File.read(path, encoding: Encoding::UTF_8)
      rescue Errno::ENOENT
        raise EditAborted, "the editor removed #{name}; nothing saved"
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
