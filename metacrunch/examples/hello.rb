# frozen_string_literal: true

# The smallest job: three records from an Array and one step. A job without
# sink writes JSON Lines to stdout.
#
#   bundle exec metacrunch run examples/hello.rb
Metacrunch.job do
  source [{"name" => "Ada"}, {"name" => "Grace"}, {"name" => "Linus"}]
  map { it.merge("greeting" => "Hello, #{it["name"]}!") }
end
