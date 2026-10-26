# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsTemplateTest < Minitest::Test

  Template = Metacrunch::Generators::Template

  CLASS = <<~RUBY
    # frozen_string_literal: true

    require "json"

    # A sink.
    class Dump

      def write(record) = record

    end
  RUBY

  def test_renders_locals_and_trims_lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.rb.erb")
      File.write(path, "<%- if loud -%>\nputs <%= name.inspect %>\n<%- end -%>\n")

      assert_equal %(puts "catalog:ids"\n), Template.render(path, name: "catalog:ids", loud: true)
    end
  end

  def test_templates_live_below_lib
    assert_equal File.expand_path("../../lib/metacrunch/templates", __dir__), Template::DIR
  end

  def test_nests_all_but_the_preamble_in_modules
    assert_equal <<~RUBY, Template.nest(CLASS, ["Marc", "Records"])
      # frozen_string_literal: true

      require "json"

      module Marc
        module Records
          # A sink.
          class Dump

            def write(record) = record

          end
        end
      end
    RUBY
  end

  def test_no_modules_leave_the_code_alone
    assert_equal CLASS, Template.nest(CLASS, [])
  end

end
