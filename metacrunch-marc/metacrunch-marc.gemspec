# frozen_string_literal: true

require_relative "lib/metacrunch/marc/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-marc"
  spec.version  = Metacrunch::Marc::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "MARC for metacrunch: MARCXML, ISO 2709 and MARC-in-JSON on one ordered record model, with a " \
                  "source and a sink"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-marc",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-marc/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", Metacrunch::Marc::VERSION
  spec.add_dependency "ox", "~> 2.14"
end
