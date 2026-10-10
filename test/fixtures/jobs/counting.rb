# frozen_string_literal: true

require_relative "lib/counting_source"

Metacrunch.job do
  source CountingSource.new
end
