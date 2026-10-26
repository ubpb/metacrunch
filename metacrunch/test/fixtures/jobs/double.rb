# frozen_string_literal: true

# Filter job: no source, no sink.
Metacrunch.job "double" do
  map { it * 2 }
end
