# frozen_string_literal: true

require "erb"
require "fileutils"
require_relative "../metacrunch"

module Metacrunch
  # What `metacrunch new` and `metacrunch generate` create (see the Readme,
  # "Generating projects and files"): Target says where a file goes, Files
  # and Skeleton compute the files, Plan writes them.
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

  end
end

require_relative "generators/target"
