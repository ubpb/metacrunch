# frozen_string_literal: true

# A transform and a job of the same name in one file: -j clean is
# ambiguous, a selection by kind is not.
Metacrunch.transform("clean") { map { it * 2 } }
Metacrunch.job("clean") { source [1] }
