module Metacrunch
  class Cli
    class Main < Thor
      desc "console", "Start a console. It uses Pry if installed, IRB otherwise."
      def console
        begin
          require "pry"
          Pry.start
        rescue LoadError
          require "irb"
          IRB.start
        end
      end
    end
  end
end
