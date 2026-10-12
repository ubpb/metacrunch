# frozen_string_literal: true

require_relative "lib/metacrunch/marcxml/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-marcxml"
  spec.version  = Metacrunch::Marcxml::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "MARCXML for metacrunch: an ordered record model, a fast parser, a source and a sink"
  spec.homepage = "https://github.com/ubpb/metacrunch-marcxml"
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
