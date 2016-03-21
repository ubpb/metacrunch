# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "metacrunch/version"

Gem::Specification.new do |spec|
  spec.name          = "metacrunch"
  spec.version       = Metacrunch::VERSION
  spec.authors       = ["René Sprotte", "Michael Sievers", "Marcel Otto"]
  spec.summary       = %q{Data processing toolkit for Ruby}
  spec.homepage      = "http://github.com/ubpb/metacrunch"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", "~> 4.2", ">= 4.2.0"
  spec.add_dependency "builder",       "~> 3.2", ">= 3.2.2"
  spec.add_dependency "net-scp",       "~> 1.2"
  spec.add_dependency "net-ssh",       "~> 2.9"
  spec.add_dependency "rubyzip",       ">= 1.0.0"
  spec.add_dependency "thor",          "~> 0.19"
  spec.add_dependency "ox",            "~> 2.1"
end
