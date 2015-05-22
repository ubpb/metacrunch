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

      def name(value = nil)
        @name = value if value.present?
        @name || @klass.to_s.demodulize.underscore.gsub!(/_command\Z/, "")
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
