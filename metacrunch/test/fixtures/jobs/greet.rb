# frozen_string_literal: true

# A command, run by path.
Metacrunch.command "greet", desc: "Log a greeting" do
  params do
    param :name, String, default: "world", desc: "Who to greet"
  end

  run { logger.info("hello, #{params.name}") }
end
