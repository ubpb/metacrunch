# frozen_string_literal: true

module Metacrunch

  # "-" as a target: stdin for Input, stdout for Output.
  STDIO = "-"

  # What Input and Output share. Internal.
  module Files

    module_function

    def path?(target) = (target.is_a?(String) && target != STDIO) || target.is_a?(Pathname)

    # The name of a target in messages: a path as given, "-" for stdin and
    # stdout, an IO's path, or else the name of its class.
    def name(target)
      return target.to_s if path?(target) || target == STDIO
      return STDIO if target.equal?($stdin) || target.equal?($stdout)

      path = target.path if target.respond_to?(:path)
      path.is_a?(String) ? path : target.class.ancestors.find(&:name).name
    end

    # The system's text of a system error, lower case first, without
    # Ruby's " @ rb_sysopen - path".
    def reason(error)
      text = error.instance_of?(SystemCallError) ? error.message : error.class.new.message
      text.sub(/\A[A-Z]/, &:downcase)
    end

  end

end
