# frozen_string_literal: true

require "json"

module Examples
  # A source: reads a JSON file that holds an array of records. The file is
  # read in each, not in the constructor, so building the job (check,
  # --help, tests with another source) reads nothing.
  class JsonArrayFile

    def initialize(path)
      @path = path
    end

    def each(&)
      JSON.parse(File.read(@path)).each(&)
    end

  end
end
