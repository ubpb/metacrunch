# frozen_string_literal: true

# A job and a command in one file; -j selects one.
Metacrunch.job("export", desc: "Export the numbers") { source [1] }
Metacrunch.command("publish", desc: "Publish the export") { run { :published } }
