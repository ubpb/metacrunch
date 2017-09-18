module Metacrunch
  class Job::Dsl::Options
    require_relative "options/dsl"

    attr_reader :options

    def initialize(argv = ARGV, require_args: false, &block)
      @options = {}
      dsl.instance_eval(&block)

      dsl.options.each do |key, opt_def|
        # Set default value
        @options[key] = opt_def[:default]

        # Register with OptionParser
        if opt_def[:args].present?
          option = parser.define(*opt_def[:args]) { |value| @options[key] = value }

          option.desc << "REQUIRED" if opt_def[:required]
          option.desc << "DEFAULT: #{opt_def[:default]}" if opt_def[:default].present?

          parser_options[key] = option
        end
      end

      # Finally parse CLI options with OptionParser
      parser.parse!(argv)

      # Make sure required options are present
      ensure_required_options!(@options)

      # Make sure args are present if required
      ensure_required_args!(argv) if require_args
    rescue OptionParser::ParseError => e
      error(e.message)
    end

  private

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = <<-BANNER.strip_heredoc
          #{ColorizedString["Job options:"].bold}
        BANNER
      end
    end

    def dsl
      @dsl ||= Dsl.new
    end

    def parser_options
      @parser_options ||= {}
    end

    def error(message)
      puts ColorizedString["Error: #{message}\n"].red.bold
      puts parser.help
      exit(1)
    end

    def ensure_required_options!(options)
      dsl.options.each do |key, opt_def|
        if opt_def[:required] && options[key].blank?
          long_option = parser_options[key].long.try(:[], 0)
          short_option = parser_options[key].short.try(:[], 0)

          error("Required job option `#{long_option || short_option}` missing.")
        end
      end
    end

    def ensure_required_args!(argv)
      if argv.blank?
        error("Required ARGS are missing.")
      end
    end

  end
end
