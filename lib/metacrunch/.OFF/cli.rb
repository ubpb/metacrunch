module Metacrunch
  class Cli
    require_relative "./cli/main"
    require_relative "./cli/base"
    require_relative "./cli/command_registry"
    require_relative "./cli/command_definition"

    def self.start(argv)
      Main.start(argv)
    end

    def self.setup(namespace, description, &block)
      klass = Class.new(Base)
      klass.namespace(namespace)

      registry = CommandRegistry.new
      yield(registry)

      registry.commands.each do |c|
        klass.register_thor_command(c)
      end

      Main.register(klass, namespace, "#{namespace} [COMMAND]", description)
    end
  end
end
