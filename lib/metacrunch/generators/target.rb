# frozen_string_literal: true

module Metacrunch
  module Generators

    # The name of a source or sink, and one part of it: a Ruby constant in
    # snake case.
    COMPONENT_NAME = /\A[a-z][a-z0-9_]*(?::[a-z][a-z0-9_]*)*\z/
    COMPONENT_PART = /\A[a-z][a-z0-9_]*\z/

    # Where `metacrunch generate` puts a file and its test, and the names in
    # them; Target.for computes it.
    #
    # - form: :name (below the project root) or :path (as given)
    # - argument: the name, or the path with .rb, as given
    # - name: the declared name of a job, transform or command; the name or
    #   base name of a source or sink
    # - file, test: absolute paths
    # - root: the project root (a Pathname) for :name, else nil
    # - modules, class_name: the constant of a source or sink, else [] and
    #   nil
    # - test_class: the class of the test
    Target = Data.define(:kind, :form, :argument, :name, :file, :test, :root, :modules, :class_name,
                         :test_class) do
      class << self

        # The target of kind (one of KINDS) for argument: a path if it
        # contains / or ., else a name. cwd: the working directory. root:
        # the project root, nil without project; a path ignores it. Raises
        # UsageError for an invalid name and for a name without project.
        def for(kind, argument, cwd:, root:)
          Names.path?(argument) ? by_path(kind, argument, cwd) : by_name(kind, argument, cwd, root)
        end

        private

        # ":" separates directories; "-" becomes "_" in file names.
        def by_name(kind, name, cwd, root)
          check_name(kind, name)
          unless root
            raise UsageError, "no #{Project::FILE} found in #{cwd} or above; give a path " \
                              "(./#{name.split(":").last}.rb) or create a project with metacrunch new"
          end

          parts = name.split(":")
          base = File.join(DIRECTORIES.fetch(kind), *parts.map { it.tr("-", "_") })
          build(kind, :name, name, name, parts, file: root.join("#{base}.rb"),
                                                test: root.join("test", "#{base}_test.rb"), root:)
        end

        def by_path(kind, path, cwd)
          raise UsageError, "#{path} is a directory; give a file name" if path.end_with?("/")

          path = "#{path}.rb" unless path.end_with?(".rb")
          base = File.basename(path, ".rb")
          check_file_name(kind, File.basename(path), base)
          build(kind, :path, path, base, [base], file: File.expand_path(path, cwd),
                                                 test: File.expand_path(File.join("test", "#{base}_test.rb"), cwd),
                                                 root: nil)
        end

        def build(kind, form, argument, name, parts, file:, test:, root:)
          constants = DECLARED.include?(kind) ? [] : parts.map { camel(it) }
          check_constant(name, constants) if constants.any?
          new(kind:, form:, argument:, name:, file: file.to_s, test: test.to_s, root:, modules: constants[0...-1],
              class_name: constants.last, test_class: test_class(kind, name, constants))
        end

        def check_name(kind, name)
          if DECLARED.include?(kind)
            unless Names.valid?(name)
              raise UsageError, "#{name.inspect} is not a valid #{kind} name; use a-z, 0-9, _ and -, " \
                                "in parts separated by :"
            end
            if Names.reserved?(name)
              raise UsageError, "#{name.inspect} is the name of a built-in command; choose another name"
            end
          elsif !COMPONENT_NAME.match?(name)
            raise UsageError, "#{name.inspect} is not a valid #{kind} name; use a-z, 0-9 and _, " \
                              "starting with a letter, in parts separated by :"
          end
        end

        def check_file_name(kind, file, base)
          if DECLARED.include?(kind)
            unless Names.valid?(base)
              raise UsageError, "#{file}: #{base.inspect} is not a valid #{kind} name; use a-z, 0-9, _ and -"
            end
            if Names.reserved?(base)
              raise UsageError, "#{file}: #{base.inspect} is the name of a built-in command; " \
                                "choose another file name"
            end
          elsif !COMPONENT_PART.match?(base)
            raise UsageError, "#{file}: #{base.inspect} is not a valid #{kind} name; use a-z, 0-9 and _, " \
                              "starting with a letter"
          end
        end

        # A source or sink must not reopen a class of Ruby or metacrunch;
        # a module may hold it ("metacrunch:lines").
        def check_constant(name, constants)
          top = constants.first
          return unless Object.const_defined?(top, false)
          return if constants.size > 1 && !Object.const_get(top, false).is_a?(Class)

          raise UsageError, "#{name.inspect} would reopen #{top}; choose another name"
        end

        def camel(part) = part.split("_").map(&:capitalize).join

        # "CatalogIdsJobTest"; "Job2goTest", since a constant starts with a
        # letter; "MarcDumpTest" for a source or sink.
        def test_class(kind, name, constants)
          return "#{constants.join}Test" if constants.any?

          words = name.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
          words.match?(/\A[A-Z]/) ? "#{words}#{kind.capitalize}Test" : "#{kind.capitalize}#{words}Test"
        end

      end

      # A job, transform or command, not a source or sink.
      def declared? = DECLARED.include?(kind)

      # The constant of a source or sink: "Marc::Dump".
      def constant = [*modules, class_name].join("::")
    end

  end
end
