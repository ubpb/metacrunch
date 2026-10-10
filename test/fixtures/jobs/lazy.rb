# frozen_string_literal: true

Metacrunch.job "lazy" do
  raise "the recipe must not run while the file is loaded"
end
