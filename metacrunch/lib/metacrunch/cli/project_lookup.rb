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
      # each file that did not load (with -v the whole error) and for each
      # name declared more than once.
      def project(logger)
        return @project if @loaded

        file = Project.find(Dir.pwd)
        @project = file && Project.load_file(file)
        @loaded = true
        log_problems(logger) if logger && @project
        @project
      end

      private

      def log_problems(logger)
        @project.load_errors.each do |file, error|
          logger.warn("#{@project.load_error_summary(file, error)} (-v after run, check or trace shows details)")
          logger.debug(error.full_message(highlight: false))
        end
        @project.duplicates.each_key { logger.warn(@project.duplicate_message(it)) }
      end

    end
  end
end
