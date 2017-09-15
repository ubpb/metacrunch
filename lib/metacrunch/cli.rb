require "optparse"

module Metacrunch
  class Cli

    ARGS_SEPERATOR = "@@"

    def run
      global_args = global_argv()
      job_args = job_argv()

      job_files = global_parser.parse(global_args)
      ARGV.clear
      job_args.each {|arg| ARGV << arg}

      run!(job_files)
    end

  private

    def global_parser
      @global_parser ||= OptionParser.new do |opts|
        opts.banner = <<-BANNER.strip_heredoc
          #{ColorizedString["Usage:"].bold}

            metacrunch [options] JOB_FILE @@ [job-options] [ARGS...]

          #{ColorizedString["Options:"].bold}
        BANNER

        opts.on("-v", "--version", "Show metacrunch version and exit") do
          show_version
        end

        opts.separator "\n"
      end
    end

    def global_options
      @global_options ||= {}
    end

    def show_version
      puts Metacrunch::VERSION
      exit(0)
    end

    def error(message)
      puts ColorizedString["Error: #{message}\n"].red.bold
      puts global_parser.help
      exit(0)
    end

    def global_argv
      index = ARGV.index(ARGS_SEPERATOR)
      if index == 0
        []
      else
        @global_argv ||= index ? ARGV[0..index-1] : ARGV
      end
    end

    def job_argv
      index = ARGV.index(ARGS_SEPERATOR)
      @job_argv ||= index ? ARGV[index+1..-1] : nil
    end

    def run!(job_files)
      if job_files.empty?
        error "You need to provide a job file."
      elsif job_files.count > 1
        error "You must provide exactly one job file."
      else
        job_filename = File.expand_path(job_files.first)
        dir = File.dirname(job_filename)

        Dir.chdir(dir) do
          run_job!(job_filename)
        end
      end
    end

    def run_job!(job_filename)
      Metacrunch::Job.define(File.read(job_filename)).run
    end

  end
end
