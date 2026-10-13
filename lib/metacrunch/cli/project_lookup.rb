# frozen_string_literal: true

module Metacrunch
  class Cli
    # Finds the project of the working directory and loads it, at most once
    # per call and only when a name needs it. The commands of one call
    # share it, so its warnings appear once.
    class ProjectLookup

      def initialize
        @loaded = false
        @project = nil
      end

      # The project, or nil without Metacrunchfile. Raises ProjectError if
      # the Metacrunchfile fails. logger, unless nil, gets a warning for
      # each file that did not load, and with -v the whole error.
      def project(logger)
        return @project if @loaded

        file = Project.find(Dir.pwd)
        @project = file && Project.load_file(file)
        @loaded = true
        log_load_errors(logger) if logger && @project
        @project
      end

      private

      def log_load_errors(logger)
        @project.load_errors.each do |file, error|
          logger.warn("#{@project.load_error_summary(file, error)} (-v for details)")
          logger.debug(error.full_message(highlight: false))
        end
      end

    end
  end
end
