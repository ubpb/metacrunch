module Metacrunch
  class Job::Dsl::Options::Dsl

    def add(name, *args, default: nil, required: false)
      if default && required
        raise ArgumentError, "You can't use `default` and `required` option at the same time."
      end

      options[name.to_sym] = {
        args: args,
        default: default,
        required: required
      }
    end

    def options
      @options ||= {}
    end

  end
end
