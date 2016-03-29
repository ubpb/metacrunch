module Metacrunch
  class Cli
    include Commander::Methods

    def run
      program :name, "metacrunch"
      program :version, Metacrunch::VERSION
      program :description, "Data processing and ETL toolkit for Ruby."

      default_command :help

      setup_run_command

      run!
    end

  private

    def setup_run_command
      command :run do |c|
        c.syntax = "metacrunch run <file>"
        c.description = "Runs a metacrunch job description."
        c.action do |args, options|
          say "TODO"
        end
      end
    end

  end
end
