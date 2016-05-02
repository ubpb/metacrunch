module Metacrunch
  class Job::Dsl::OptionSupport

    def register_options(args, &block)
      options = {}
      registry.instance_eval(&block)

      registry.each do |key, opt_def|
        # Set default value
        options[key] = opt_def[:default]

        # Register with OptionParser
        if opt_def[:args].present?
          option = parser.define(*opt_def[:args]) { |value| options[key] = value }

          option.desc << "REQUIRED" if opt_def[:required]
          option.desc << "DEFAULT: #{opt_def[:default]}" if opt_def[:default].present?

          parser_options[key] = option
        end
      end

      # Finally parse CLI args with OptionParser
      parser.parse!(args || [])

      # Make sure required options are present
      ensure_required_options!(options)

      options
    end

  private

    def parser
      @parser ||= OptionParser.new do |parser|
        parser.banner = "Usage: metacrunch run [options] JOB_FILE @@ [job-options] [ARGS]\nJob options:"
      end
    end

    def parser_options
      @parser_options ||= {}
    end

    def registry
      @registry ||= OptionRegistry.new
    end

    def ensure_required_options!(options)
      registry.each do |key, opt_def|
        if opt_def[:required] && options[key].blank?
          long_option = parser_options[key].long.try(:[], 0)
          short_option = parser_options[key].short.try(:[], 0)

          puts "Error: Required job option `#{long_option || short_option}` missing."
          puts parser.help

          exit(1)
        end
      end
    end

  private

    class OptionRegistry

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
