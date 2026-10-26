# frozen_string_literal: true

# Prints each record on stdout.
class PrintingSink

  def write(record)
    $stdout.puts(record)
  end

end
