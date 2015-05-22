source 'https://rubygems.org'

gemspec

gem "rake"
gem "rspec", "~> 3.2.0"

if !ENV["CI"]
  group :development do
    gem "hashdiff"
    gem "pry",                "~> 0.9.12.6"
    gem "pry-byebug",         "<= 1.3.2"
    gem "pry-rescue",         "~> 1.4.1", github: "ConradIrwin/pry-rescue", branch: :master
    gem "pry-stack_explorer", "~> 0.4.9.1"
    gem "pry-syntax-hacks",   "~> 0.0.6"
  end
end
