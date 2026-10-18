# frozen_string_literal: true

module Metacrunch
  module Generators
    # The file and the test of a job, transform, command, source or sink,
    # from the templates of its kind: KIND/file.rb.erb, and
    # KIND/test.rb.erb for a name or KIND/path_test.rb.erb for a path.
    module Files

      module_function

      # The Plan for target. desc: the desc: of a job, transform or
      # command, or nil. test: whether the test is part of it.
      def plan(target, desc: nil, test: true)
        locals = template_locals(target, desc)
        code = Template.render(File.join(target.kind, "file.rb.erb"), **locals)
        plan = Plan.new.add(target.file, Template.nest(code, target.modules), executable: target.declared?)
        return plan unless test

        template = target.form == :name ? "test.rb.erb" : "path_test.rb.erb"
        plan.add(target.test, Template.render(File.join(target.kind, template), **locals))
      end

      # target and desc, and for the templates:
      # - run: what follows `metacrunch` to run it ("catalog:ids", "run tools/fix.rb")
      # - helper: test/test_helper relative to the test (name form)
      # - file: the file relative to the test
      # - library: the file to require from a test, below lib/ (name form)
      def template_locals(target, desc)
        test_dir = File.dirname(target.test)
        by_name = target.form == :name
        {
          target:, desc:,
          run: by_name ? target.name : "run #{target.argument}",
          helper: (Generators.relative(target.root.join("test", "test_helper").to_s, test_dir) if by_name),
          file: Generators.relative(target.file, test_dir),
          library: (Generators.relative(target.file, target.root.join("lib").to_s).delete_suffix(".rb") if by_name)
        }
      end

    end
  end
end
