# frozen_string_literal: true

require_relative "lib/metacrunch/redis/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-redis"
  spec.version  = Metacrunch::Redis::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "Redis for metacrunch: a queue between jobs, and a source and a sink for keys, on Redis and Valkey"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-redis",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-redis/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  spec.add_dependency "metacrunch", Metacrunch::Redis::VERSION
  spec.add_dependency "redis-client", "~> 0.31"
end
