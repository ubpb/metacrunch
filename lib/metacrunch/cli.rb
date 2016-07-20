require "optparse"

module Metacrunch
  class Cli
    ARGS_SEPERATOR = "@@"

    def run
      job_files = global_parser.parse!(global_argv)

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

        opts.on("-n INTEGER", "--number-of-processes INTEGER", Integer, "Number of parallel processes to run the job. Source needs to support this. DEFAULT: 1") do |n|
          error("--number-of-procs must be > 0") if n <= 0
          global_options[:number_of_processes] = n
        end

        opts.separator "\n"
      end
    end

    def global_options
      @global_options ||= {
        number_of_processes: 1
      }
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
      if job_files.first == "run"
        puts ColorizedString["WARN: Using 'run' is deprecated. Just use 'metacrunch [options] JOB_FILE @@ [job-options] [ARGS...]'\n"].yellow.bold
        job_files = job_files[1..-1]
      end

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
      if global_options[:number_of_processes] > 1
        process_indicies = (0..(global_options[:number_of_processes] - 1)).to_a

        Parallel.each(process_indicies) do |process_index|
          Metacrunch::Job.define(
            File.read(job_filename),
            filename: job_filename,
            args: job_argv,
            number_of_processes: global_options[:number_of_processes],
            process_index: process_index
          ).run
        end
      else
        Metacrunch::Job.define(
          File.read(job_filename),
          filename: job_filename,
          args: job_argv
        ).run
      end
    end

  end
end
