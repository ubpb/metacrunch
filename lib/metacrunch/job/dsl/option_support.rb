module Metacrunch
  class Job::Dsl::OptionSupport

    def register_options(args, &block)
      registry = OptionProxy.new
      registry.instance_eval(&block)

      options = {}

      OptionParser.new do |parser|
        parser.banner = "Job specific options:"
        registry.each do |key, opt_def|
          options[key] = opt_def[:default]
          parser.on(*opt_def[:args]) do |value|
            options[key] = value
          end
        end
      end.parse!(args)

      options
    end

    class OptionProxy

      def add(name, *args, default:)
        options[name.to_sym] = {
          args: args,
          default: default
        }
      end

      def each(&block)
        options.each(&block)
      end

    private

      def options
        @options ||= {}
      end
    end

  end
end
