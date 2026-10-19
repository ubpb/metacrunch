# frozen_string_literal: true

require "erb"
require "prism"
require "fileutils"
require_relative "../metacrunch"

module Metacrunch
  # What `metacrunch new` and `metacrunch generate` create (see
  # docs/projects.md, "Generating projects and files"): Target says where a
  # file goes, Files and Skeleton compute the files, Plan writes them.
  module Generators

    KINDS = ["job", "transform", "command", "source", "sink"].freeze
    KIND_LIST = "job, transform, command, source or sink"
    # The kinds that declare a name in the project; sources and sinks are
    # classes.
    DECLARED = ["job", "transform", "command"].freeze
    DIRECTORIES = {"job" => "jobs", "transform" => "transforms", "command" => "commands", "source" => "lib",
                   "sink" => "lib"}.freeze

    module_function

    # path relative to dir, for messages: "jobs/x.rb", "../jobs/x.rb".
    def relative(path, dir) = Pathname(path).relative_path_from(Pathname(dir)).to_s

    # A double-quoted Ruby literal of text that keeps its printable
    # characters: String#inspect escapes all but ASCII under LANG=C.
    def literal(text)
      runs = text.scan(/[[:ascii:]]+|[^[:ascii:]]+/).map do |run|
        run.ascii_only? || !run.match?(/\A[[:print:]]+\z/) ? run.inspect[1...-1] : run
      end
      "\"#{runs.join}\""
    end

  end
end

require_relative "generators/target"
require_relative "generators/template"
require_relative "generators/plan"
require_relative "generators/files"
require_relative "generators/skeleton"
