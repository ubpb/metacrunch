# frozen_string_literal: true

# Takes long enough for the progress display to draw.
Metacrunch.job do
  source [1, 2]
  map do |record|
    sleep(0.2)
    record
  end
end
