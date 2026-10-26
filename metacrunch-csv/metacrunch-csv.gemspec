# frozen_string_literal: true

require_relative "lib/metacrunch/csv/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-csv"
  spec.version  = Metacrunch::Csv::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "CSV for metacrunch: a source and a sink on Ruby's csv"
  spec.homepage = "https://github.com/ubpb/metacrunch-csv"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"
end
