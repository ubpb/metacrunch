require File.expand_path("../lib/metacrunch/mab2/version", __FILE__)

Gem::Specification.new do |s|
  s.authors       = ["René Sprotte", "Michael Sievers", "Marcel Otto"]
  s.email         = "r.sprotte@ub.uni-paderborn.de"
  s.summary       = %q{MAB2 tools for metacrunch}
  s.description   = s.summary
  s.homepage      = "http://github.com/ubpb/metacrunch-mab2"
  s.licenses      = ["MIT"]

  s.files         = `git ls-files`.split($\)
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.name          = "metacrunch-mab2"
  s.require_paths = ["lib"]
  s.version       = Metacrunch::Mab2::VERSION

  s.required_ruby_version = ">= 2.2.0"

  s.add_dependency "metacrunch",   ">= 2.1.0.pre1"
  s.add_dependency "htmlentities", "~> 4.3"
  s.add_dependency "ox",           "~> 2.1"
end
