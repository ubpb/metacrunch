source "https://rubygems.org"

gemspec

group :development do
  gem "bundler",   ">= 1.11.2"
  gem "rake",      ">= 11.1"
  gem "rspec",     ">= 3.0.0",  "< 4.0.0"
  gem "simplecov", ">= 0.11.0"

  if !ENV["CI"]
    gem "hashdiff",   ">= 0.3.0"
    gem "pry-byebug", "~> 3.3.0"
    gem "pry-rescue", "~> 1.4.2"
    gem "pry-state",  "~> 0.1.7"
  end
end

group :test do
  gem "codeclimate-test-reporter", ">= 0.5.0", require: nil
end
