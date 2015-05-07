require "metacrunch/pipeline"

module Metacrunch
  class Cli
    class Main < Thor
      desc "execute", "Excecute a pipeline configuration"
      def execute(*args)
        Metacrunch::Pipeline.new(*args).start
      end
    end
  end
end
