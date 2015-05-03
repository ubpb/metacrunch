module Metacrunch
  class Cli
    class Base < Thor
      no_commands do
        def self.register_thor_command(command_definition)
          desc(command_definition.usage, command_definition.desc)

          command_definition.options.each do |key, value|
            option(key, value)
          end

          define_method(command_definition.name) do |*params|
            run_command(command_definition.command_class, params)
          end
        end

        def run_command(command, params = [])
          klass = command.class == Class ? command : command.to_s.constantize
          raise ArgumentError, "command must be a Metacrunch::Command class" unless klass < Metacrunch::Command

          command = klass.new(shell, options, params)
          command.pre_perform
          command.perform
          command.post_perform
        end
      end
    end
  end
end
