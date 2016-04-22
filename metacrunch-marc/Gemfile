source "https://rubygems.org"

gemspec

gem "metacrunch", ">= 2.1.0", github: "ubpb/metacrunch", branch: "master"

group :development do
  gem "bundler",      ">= 1.7"
  gem "rake",         ">= 11.1"
  gem "rspec",        ">= 3.0.0",  "< 4.0.0"
  gem "simplecov",    ">= 0.11.0"

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
