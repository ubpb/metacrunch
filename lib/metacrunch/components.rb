# frozen_string_literal: true

module Metacrunch

  # Passed to open(context) of sources, steps and sinks.
  OpenContext = Data.define(:params, :logger)

  # Opens and closes components: sources, step callables and sinks.
  module Components

    module_function

    # Opens the components in order. Each one is appended to opened once it
    # is open, so after a failed open, opened holds what has to be closed.
    def open(components, context, opened)
      components.each do |component|
        component.open(context) if component.respond_to?(:open)
        opened << component
      end
    end

    # Closes the opened components in reverse order and returns the first
    # error, after trying to close all of them. A signal raised while
    # closing (e.g. SIGPIPE from a writer whose reader went away) is raised
    # again once everything is closed.
    def close(opened, logger)
      first_error = nil
      signal = nil
      opened.reverse_each do |component|
        component.close if component.respond_to?(:close)
      rescue *Engine::RECOVERABLE => e
        logger.error("closing #{component.class} failed: #{e.class}: #{e.message}")
        first_error ||= e
      rescue SignalException => e
        signal ||= e
      end
      raise signal if signal

      first_error
    end

  end

end
