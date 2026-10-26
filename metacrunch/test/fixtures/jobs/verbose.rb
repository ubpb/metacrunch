# frozen_string_literal: true

# Logs a debug message before it runs.
Metacrunch.job do
  source [1]
  before { logger.debug("debug message") }
end
