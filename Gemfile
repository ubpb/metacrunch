source "https://rubygems.org"

gemspec

group :development do
  gem "bundler", ">= 1.15"
  gem "rake",    ">= 12.1"
  gem "rspec",   ">= 3.5.0", "< 4.0.0"
  gem "sqlite3", ">= 1.3.11"

  if !ENV["CI"]
    gem "pry-byebug", ">= 3.5.0"
  end
end

group :test do
  gem "codeclimate-test-reporter", ">= 1.0.8"
  gem "simplecov", ">= 0.13.0"
end
