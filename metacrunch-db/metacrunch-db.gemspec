# frozen_string_literal: true

require_relative "lib/metacrunch/db/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch-db"
  spec.version  = Metacrunch::Db::VERSION
  spec.authors  = ["René Sprotte"]
  spec.summary  = "Relational databases for metacrunch: a source and a sink for SQLite, PostgreSQL, MySQL and MariaDB"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-db",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-db/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "License.txt", "Readme.md"]

  # No driver: the project adds the one of its database (pg, mysql2, trilogy, sqlite3, ...).
  spec.add_dependency "metacrunch", Metacrunch::Db::VERSION
  spec.add_dependency "sequel", "~> 5.109"
end
