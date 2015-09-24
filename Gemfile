source "https://rubygems.org"

# Specify your gem's dependencies in your gemspec
gemspec

group :development do
  gem "bundler"
  gem "nokogiri"
  gem "rake"
  gem "rspec",           ">= 3.0.0",  "< 4.0.0"
  gem "simplecov",       ">= 0.8.0"

  if !ENV["CI"]
    gem "hashdiff"
    gem "pry",                "~> 0.9.12.6"
    gem "pry-byebug",         "<= 1.3.2"
    gem "pry-rescue",         "~> 1.4.2"
    gem "pry-stack_explorer", "~> 0.4.9.1"
    gem "pry-syntax-hacks",   "~> 0.0.6"
  end
end

group :test do
  gem "codeclimate-test-reporter", require: nil
end
