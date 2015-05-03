module Metacrunch
  class Cli
    class CommandDefinition
      def initialize(command_class, description)
        @klass       = command_class
        @name        = nil
        @description = description
        @usage       = nil
        @options     = {}
      end

      def command_class(value = nil)
        @klass if value
        @klass
      end

      def name
        name = @klass.to_s.demodulize.underscore
        name.gsub!(/_command\Z/, "")
      end

      def usage(value = nil)
        @usage = value if value.present?
        @usage || name
      end

      def desc(value = nil)
        @description = value if value.present?
        @description
      end

      def option(name, options = {})
        @options[name] = options
      end

      def options
        @options
      end
    end
  end
end
