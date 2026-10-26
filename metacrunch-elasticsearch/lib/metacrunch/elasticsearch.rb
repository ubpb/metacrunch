# frozen_string_literal: true

require "json"
require "uri"
require "elasticsearch"
require "metacrunch"
require_relative "elasticsearch/version"
require_relative "elasticsearch/errors"
require_relative "elasticsearch/names"
require_relative "elasticsearch/connection"
require_relative "elasticsearch/definition"

module Metacrunch
  # Elasticsearch for metacrunch: a source (Reader), a bulk sink (Writer),
  # lookups for steps (Search) and index operations (Indices), which the
  # commands in COMMANDS wrap. Inside this module, ::Elasticsearch is the
  # client gem.
  module Elasticsearch

    # The command files (es:create-index, ...). A project opts in with
    # Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS.
    COMMANDS = File.expand_path("elasticsearch/commands/*.rb", __dir__)

  end
end
