# frozen_string_literal: true

module Metacrunch
  class Cli
    # Base class of the commands. #run parses the command's options up to
    # the first argument that is not an option, then #execute gets the rest;
    # it returns the exit code. Subclasses define NAME, SUMMARY, USAGE,
    # #define_options and #execute.
    class Command

      def initialize(streams)
        @stdin = streams.stdin
        @stdout = streams.stdout
        @stderr = streams.stderr
        @env = streams.env
        @log_level = Logger::INFO
        @help = false
      end

      def run(argv)
        argv = argv.dup
        parser = option_parser
        parser.order!(argv)
        return show(parser.help) if @help

        execute(argv)
      rescue OptionParser::ParseError, JobLoadError, ParamError, UsageError => e
        usage_error(e.message)
      rescue SignalException => e
        interrupted(e)
      rescue *Engine::RECOVERABLE => e
        logger.error(e.full_message(highlight: false))
        EXIT_CODES[:aborted]
      end

      private

      def option_parser
        OptionParser.new do |parser|
          # No built-in --help and --version (they print and exit), and no
          # abbreviated options.
          parser.base.long.clear
          parser.require_exact = true
          parser.banner = "Usage: metacrunch #{self.class::USAGE}"
          parser.separator("")
          parser.separator("#{self.class::SUMMARY}.")
          parser.separator("")
          define_options(parser)
          parser.on("-h", "--help", "Show this help") { @help = true }
        end
      end

      def define_options(_parser) = nil

      def logger
        @logger ||= Metacrunch.build_logger(log_output).tap { it.level = @log_level }
      end

      # Where logs go; run sends them through the progress display.
      def log_output = @stderr

      # Exit code 128 + signal number, as shells report it; exe/metacrunch
      # then ends by the signal. A closed stdout (SIGPIPE) is not worth a
      # warning: the reader of the pipe stopped on purpose, e.g. head.
      def interrupted(signal)
        message = "interrupted by SIG#{Signal.signame(signal.signo)}"
        if signal.signo == Signal.list.fetch("PIPE")
          logger.debug(message)
        else
          logger.warn(message)
        end
        128 + signal.signo
      end

      def show(text)
        @stdout.puts(text)
        EXIT_CODES[:ok]
      end

      def usage_error(message)
        @stderr.puts("Error: #{message}", "Usage: metacrunch #{self.class::USAGE}")
        EXIT_CODES[:usage]
      end

    end
  end
end
