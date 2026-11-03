# frozen_string_literal: true

require_relative "lib/metacrunch/ai/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-ai"
  spec.version  = Metacrunch::Ai::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "AI steps for metacrunch: embeddings through the OpenAI embeddings API and compatible servers"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-ai",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-ai/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", Metacrunch::Ai::VERSION
  spec.add_dependency "nokogiri", "~> 1.19"
end
