# frozen_string_literal: true

require_relative "lib/metacrunch/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch"
  spec.version  = Metacrunch::VERSION
  spec.authors  = ["René Sprotte", "Michael Sievers", "Marcel Otto"]
  spec.summary  = "Data processing and ETL toolkit for Ruby"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "lib/**/*.erb", "exe/*", "CHANGELOG.md", "License.txt", "Readme.md", "docs/*.md"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { |path| File.basename(path) }

  spec.add_dependency "logger", ">= 1.6"
end
