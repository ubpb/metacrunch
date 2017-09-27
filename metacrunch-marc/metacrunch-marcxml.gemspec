# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "metacrunch/marcxml/version"

Gem::Specification.new do |spec|
  spec.name          = "metacrunch-marcxml"
  spec.version       = Metacrunch::Marcxml::VERSION
  spec.authors       = ["René Sprotte"]
  spec.email         = "r.sprotte@ub.uni-paderborn.de"
  spec.summary       = %q{MARCXML package for the metacrunch ETL toolkit.}
  spec.homepage      = "http://github.com/ubpb/metacrunch-marcxml"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 5.1"
  spec.add_dependency "htmlentities",  ">= 4.3"
  spec.add_dependency "ox",            ">= 2.8"
end

