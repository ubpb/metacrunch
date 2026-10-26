# frozen_string_literal: true

module Metacrunch
  module Generators
    # The ERB templates in lib/metacrunch/templates.
    module Template

      DIR = File.expand_path("../templates", __dir__)
      # A line at the top of a file that stays outside the modules nest
      # wraps around the rest: the magic comment, a require, a blank line.
      PREAMBLE = /\A(?:# frozen_string_literal: true|require .*)?\n\z/

      module_function

      # The template at path, relative to DIR or absolute, with locals as
      # local variables. Lines in <%- ... -%> leave no line behind.
      def render(path, **locals)
        ERB.new(File.read(File.expand_path(path, DIR)), trim_mode: "-").result_with_hash(locals)
      end

      # code with all but its preamble wrapped in modules, outermost first,
      # two spaces deeper per module.
      def nest(code, modules)
        lines = code.lines
        preamble = lines.take_while { PREAMBLE.match?(it) }
        body = lines.drop(preamble.size)
        modules.reverse_each { |name| body = ["module #{name}\n", *body.map { indent(it) }, "end\n"] }
        [*preamble, *body].join
      end

      def indent(line) = line == "\n" ? line : "  #{line}"

    end
  end
end
