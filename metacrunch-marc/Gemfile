source "https://rubygems.org"

gemspec

group :development do
  gem "bundler", ">= 1.15"
  gem "rake",    ">= 12.1"
  gem "rspec",   ">= 3.5.0", "< 4.0.0"

  if !ENV["CI"]
    gem "pry-byebug", ">= 3.5.0"
  end
end

group :test do
  gem "simplecov", ">= 0.15.0"
end
