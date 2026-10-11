#!/usr/bin/env metacrunch
# frozen_string_literal: true

# The smallest job: three records from an Array and one step. A job without
# sink writes JSON Lines to stdout.
#
#   metacrunch run examples/hello.rb
#   ./examples/hello.rb                  # the file is executable
Metacrunch.job do
  source [{"name" => "Ada"}, {"name" => "Grace"}, {"name" => "Linus"}]
  map { it.merge("greeting" => "Hello, #{it["name"]}!") }
end
