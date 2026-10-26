# frozen_string_literal: true

require_relative "lib/metacrunch/xlsx/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-xlsx"
  spec.version  = Metacrunch::Xlsx::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "XLSX for metacrunch: a sink that streams Excel files"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-xlsx",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-xlsx/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", Metacrunch::Xlsx::VERSION
  spec.add_dependency "zip_kit", "~> 6.4"
end
