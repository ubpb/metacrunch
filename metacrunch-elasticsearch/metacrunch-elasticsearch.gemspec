# frozen_string_literal: true

require_relative "lib/metacrunch/elasticsearch/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-elasticsearch"
  spec.version  = Metacrunch::Elasticsearch::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "Elasticsearch for metacrunch: a source, a bulk sink and commands for indices and aliases"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-elasticsearch",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-elasticsearch/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  # The client's major version must match the server's: 8.x for Elasticsearch 8, 9.x for Elasticsearch 9.
  spec.add_dependency "elasticsearch", ">= 8.0", "< 10"
  spec.add_dependency "json", ">= 2.8"
  spec.add_dependency "metacrunch", Metacrunch::Elasticsearch::VERSION
end
