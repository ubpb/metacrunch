# frozen_string_literal: true

# A transform, a job and a command in one file; -j selects one.
Metacrunch.transform("trim", desc: "Strip strings") { map(&:strip) }
Metacrunch.job("lines", desc: "Print the lines") { source [" a "] }
Metacrunch.command("tidy", desc: "Tidy up") { run { :tidy } }
