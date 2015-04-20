module Metacrunch
  module Mab2
    class Cli < Thor
      namespace "mab2"
    end
  end
end

Metacrunch::Cli.register(Metacrunch::Mab2::Cli, "mab2", "mab2 <command>", "MAB2 utilities")
