module Metacrunch
  class Cli
    ARGS_SEPERATOR = "@@"

    def run
      runner = create_runner(program_args)
      setup_run_command(runner, job_args)
      runner.run!
    end

  private

    def create_runner(program_args)
      runner = Commander::Runner.new(program_args)

      runner.program :name, "metacrunch"
      runner.program :version, Metacrunch::VERSION
      runner.program :description, "Data processing and ETL toolkit for Ruby."
      runner.default_command :help

      runner
    end

    def setup_run_command(runner, job_args)
      runner.command :run do |c|
        c.syntax = "metacrunch run [options] FILE [@@ job_options]"
        c.description = "Runs a metacrunch job description."
        c.action do |args, program_options|
          if args.empty?
            say "You need to provide a job description file."
            exit(1)
          else
            args.each do |filename|
              contents = File.read(filename)
              context = Metacrunch::Job.define(contents, filename: filename, args: job_args)
              context.run
            end
          end
        end
      end
    end

    def program_args
      index = ARGV.index(ARGS_SEPERATOR)
      index ? ARGV[0..index-1] : ARGV
    end

    def job_args
      index = ARGV.index(ARGS_SEPERATOR)
      index ? ARGV[index+1..-1] : ARGV
    end

  end
end
