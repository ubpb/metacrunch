# frozen_string_literal: true

module Metacrunch
  module Generators
    # The files of a new project (`metacrunch new`): a Metacrunchfile that
    # loads jobs, transforms and commands, a Gemfile and a Rakefile, the
    # directories for them and for lib/, and a test of the project.
    module Skeleton

      # Path in the project => template in templates/project, or nil for an
      # empty file that keeps the directory in Git.
      FILES = {
        "Metacrunchfile" => "Metacrunchfile.erb", "Gemfile" => "Gemfile.erb", "Rakefile" => "Rakefile.erb",
        "jobs/.keep" => nil, "transforms/.keep" => nil, "commands/.keep" => nil, "lib/.keep" => nil,
        "test/test_helper.rb" => "test_helper.rb.erb", "test/project_test.rb" => "project_test.rb.erb"
      }.freeze

      module_function

      # The Plan of a project in root, an absolute path. version: the
      # metacrunch version the Gemfile asks for.
      def plan(root, version: VERSION)
        metacrunch = gem_line(version)
        FILES.each_with_object(Plan.new) do |(path, template), plan|
          content = template ? Template.render(File.join("project", template), metacrunch:) : ""
          plan.add(File.join(root, path), content)
        end
      end

      # The Gemfile line of metacrunch: "~> MAJOR.MINOR" for a release; Git
      # for a prerelease, which RubyGems does not have.
      def gem_line(version)
        version = Gem::Version.new(version)
        return %(gem "metacrunch", github: "ubpb/metacrunch", branch: "metacrunch-ng") if version.prerelease?

        %(gem "metacrunch", "~> #{version.segments.first(2).join(".")}")
      end

    end
  end
end
