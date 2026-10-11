# frozen_string_literal: true

# Emits five records as JSON Lines on stdout.
Metacrunch.job do
  source((1..5).map { {"n" => it} })
end
