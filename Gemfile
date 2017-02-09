source "https://rubygems.org"

gemspec

group :development do
  gem "bundler",      ">= 1.7"
  gem "rake",         ">= 11.1"
  gem "rspec",        ">= 3.5.0",  "< 4.0.0"
  gem "simplecov",    ">= 0.11.0"
  gem "sqlite3",      ">= 1.3.11", platform: :ruby
  gem "jdbc-sqlite3", ">= 3.8", platform: :jruby

  if !ENV["CI"]
    gem "hashdiff",   ">= 0.3.0", platform: :ruby
    gem "pry-byebug", ">= 3.3.0", platform: :ruby
    gem "pry-rescue", ">= 1.4.2", platform: :ruby
    gem "pry-state",  ">= 0.1.7", platform: :ruby
  end
end

group :test do
  gem "codeclimate-test-reporter", ">= 0.5.0", require: nil
end
