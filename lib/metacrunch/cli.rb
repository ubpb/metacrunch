module Metacrunch
  class Cli

    def self.start(argv)
      Main.start(argv)
    end

    def self.setup(namespace, description, &block)
      klass = Class.new(Base)
      klass.namespace(namespace)

      registry = CommandRegistry.new
      yield(registry)

      registry.commands.each do |c|
        klass.register_thor_command(
          c.klass,
          c.name,
          c.instance_variable_get("@description"),
          c.instance_variable_get("@options"))
      end

      Main.register(klass, namespace, "#{namespace} [COMMAND]", description)
    end

  private

    class CommandRegistry
      attr_reader :commands

      def initialize
        @commands = []
      end

      def register(klass, description = nil, &block)
        command = CommandDefinition.new(klass, description)
        yield(command) if block_given?
        @commands << command
      end

      class CommandDefinition
        attr_reader :klass

        def initialize(klass, description)
          @klass       = klass
          @description = description
          @options     = {}
        end

        def name
          name = @klass.to_s.demodulize.underscore
          name.gsub!(/_command\Z/, "")
        end

        def description(value)
          @description = value
        end

        def option(name, options = {})
          @options[name] = options
        end
      end
    end

    class Main < Thor
      # Define metacrunch root commands here
    end

    class Base < Thor
      no_commands do
        def self.register_thor_command(klass, name, description, options = {})
          desc(name, description)

          options.each do |key, value|
            option(key, value)
          end

          define_method(name) do |*params|
            run_command(klass, params)
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
