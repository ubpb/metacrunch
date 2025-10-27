require "optparse"

class Metacrunch::Cli

  def run
    # Parse global options on order
    job_argv = global_parser.order(ARGV)
    # The first of the unparsed arguments is by definition the filename
    # of the job.
    job_file = job_argv[0]
    # Manipulate ARGV so that the option handling for the job can work
    ARGV.clear
    job_argv[1..-1]&.each {|arg| ARGV << arg}
    # Delete the old separator symbol for backward compatability
    ARGV.delete_if{|arg| arg == "@@"}
    # Finally run the job
    run!(job_file)
  rescue OptionParser::ParseError => e
    error(e.message)
  end

private

  def global_parser
    @global_parser ||= OptionParser.new do |opts|
      opts.banner = <<-BANNER.strip_heredoc
        #{ColorizedString["Usage:"].bold}

          metacrunch [options] JOB_FILE [job-options] [ARGS...]

        #{ColorizedString["Options:"].bold}
      BANNER

      opts.on("-v", "--version", "Show metacrunch version and exit") do
        show_version
      end
    end
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

  def run!(job_file)
    if job_file.blank?
      error "You need to provide a job file."
    elsif !File.exist?(job_file)
      error "The file `#{job_file}` doesn't exist."
    else
      job_filename = File.expand_path(job_file)
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
