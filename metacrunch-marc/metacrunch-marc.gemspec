# frozen_string_literal: true

require_relative "lib/metacrunch/marc/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-marc"
  spec.version  = Metacrunch::Marc::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "MARC for metacrunch: MARCXML, ISO 2709 and MARC-in-JSON on one ordered record model, with a " \
                  "source and a sink"
  spec.homepage = "https://github.com/ubpb/metacrunch-marc"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"
  spec.add_dependency "ox", "~> 2.14"
end
