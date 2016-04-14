module Metacrunch
  class Cli
    ARGS_SEPERATOR = "@@"

    def run
      init_commander!
      init_run_command!
      run_commander!
    end

  private
    def commander
      @commander ||= Commander::Runner.new(metacrunch_args)
    end

    def init_commander!
      commander.program :name, "metacrunch"
      commander.program :version, Metacrunch::VERSION
      commander.program :description, "Data processing and ETL toolkit for Ruby."
      commander.default_command :help
    end

    def run_commander!
      commander.run!
    end

    def init_run_command!
      commander.command :run do |c|
        c.syntax = "metacrunch run [options] FILE [@@ job_options]"
        c.description = "Runs a metacrunch job description."
        c.option "--install", "Install job dependencies using Bundler"

        c.action do |filenames, program_options|
          if filenames.empty?
            say "You need to provide a job description file."
            exit(1)
          elsif filenames.count > 1
            say "You must provide exactly one job description file."
          else
            filename = filenames.first
            contents = File.read(filename)
            context = Metacrunch::Job.define(contents, filename: filename, args: job_args, install_dependencies: program_options.install)
            context.run
          end
        end
      end
    end

    def metacrunch_args
      index = ARGV.index(ARGS_SEPERATOR)
      @metacrunch_args ||= index ? ARGV[0..index-1] : ARGV
    end

    def job_args
      index = ARGV.index(ARGS_SEPERATOR)
      @job_args ||= index ? ARGV[index+1..-1] : nil
    end

  end
end
