# frozen_string_literal: true

require_relative "lib/metacrunch/xlsx/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-xlsx"
  spec.version  = Metacrunch::Xlsx::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "XLSX for metacrunch: a sink that streams Excel files"
  spec.homepage = "https://github.com/ubpb/metacrunch-xlsx"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"
  spec.add_dependency "zip_kit", "~> 6.4"
end
