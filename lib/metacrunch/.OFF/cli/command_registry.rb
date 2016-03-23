module Metacrunch
  class Cli
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
    end
  end
end
