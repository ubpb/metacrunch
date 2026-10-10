# frozen_string_literal: true

Metacrunch.job("first") { source [] }
Metacrunch.job("second") { source [1] }
