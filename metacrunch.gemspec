require File.expand_path("../lib/metacrunch/version", __FILE__)

Gem::Specification.new do |s|
  s.authors       = ["René Sprotte", "Michael Sievers", "Marcel Otto"]
  s.email         = "r.sprotte@ub.uni-paderborn.de"
  s.summary       = %q{Data processing toolkit for Ruby}
  s.description   = s.summary
  s.homepage      = "http://github.com/ubpb/metacrunch"
  s.licenses      = ["MIT"]

  s.files         = `git ls-files`.split($\)
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.name          = "metacrunch"
  s.require_paths = ["lib"]
  s.version       = Metacrunch::VERSION
  s.bindir        = "bin"
  s.executables   = ["metacrunch"]

  s.required_ruby_version = ">= 2.2.0"

  s.add_dependency "activesupport", "~> 4.2", ">= 4.2.0"
  s.add_dependency "builder",       "~> 3.2", ">= 3.2.2"
  s.add_dependency "highline",      "~> 1.7"
  s.add_dependency "net-scp",       "~> 1.2"
  s.add_dependency "net-ssh",       "~> 2.9"
  s.add_dependency "parallel",      "~> 1.6", ">= 1.6.0"
  s.add_dependency "rubyzip",       ">= 1.0.0"
  s.add_dependency "thor",          "~> 0.19"
  s.add_dependency "ox",            "~> 2.1"
end
