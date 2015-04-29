module Metacrunch
  class Cli < Thor
  end

  class Cli::Base < Thor
  private

    def run_command(command, command_params = {})
      clazz = command.class == Class ? command : command.to_s.constantize
      raise ArgumentError, "command must be a Metacrunch::Command class" unless clazz < Metacrunch::Command

      clazz.new(shell: shell, options: options).call(command_params)
    end
  end
end
