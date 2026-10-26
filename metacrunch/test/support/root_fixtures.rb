# frozen_string_literal: true

# Recipes that use root, and a project with them, for RootTest and
# RootCliTest. Never name a test's block variable root: it would shadow
# root inside the recipe blocks of the test.
module RootFixtures

  METACRUNCHFILE = "Metacrunch.load_files \"jobs/**/*.rb\", \"transforms/**/*.rb\", \"commands/**/*.rb\"\n"

  ROOTED = <<~'RUBY'
    # frozen_string_literal: true

    Metacrunch.job "rooted" do
      params { param :input, String, default: root.join("data/in.txt") }

      source File.readlines(params.input, chomp: true)
      before { logger.info("root #{root}") }
      map { |line| "#{line}@#{root.basename}" }
    end
  RUBY

  LABELED = <<~'RUBY'
    # frozen_string_literal: true

    Metacrunch.transform("label") { map { |line| "#{line}:#{root.basename}" } }
    Metacrunch.job("labeled") { source ["x"]; use "label" }
  RUBY

  WHERE = <<~RUBY
    # frozen_string_literal: true

    Metacrunch.command "where" do
      params { param :out, String, default: root.join("out") }

      run { [params.out, root.to_s] }
    end
  RUBY

  # Writes the project with every recipe above and its data below dir.
  def write_root_project(dir)
    write_file(dir, "Metacrunchfile", METACRUNCHFILE)
    write_file(dir, "jobs/rooted.rb", ROOTED)
    write_file(dir, "jobs/labeled.rb", LABELED)
    write_file(dir, "commands/where.rb", WHERE)
    write_file(dir, "data/in.txt", "a\n")
  end

end
