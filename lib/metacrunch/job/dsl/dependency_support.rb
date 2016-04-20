module Metacrunch
  class Job::Dsl::DependencySupport

    def initialize(install: false, &block)
      proxy = DependencyProxy.new
      proxy.instance_eval(&block)

      if install
        puts "Installing dependencies..."
        proxy.each do |name, options|
          if options[:version]
            `gem install #{name} -v "#{options[:version]}"`
          else
            `gem install #{name}`
          end
        end

        exit(0)
      end

      proxy.each do |name, options|
        begin
          if options[:version]
            gem(name, options[:version])
          else
            gem(name)
          end
        rescue Gem::LoadError => e
          puts "#{e.message}. Use 'metacrunch run --install FILE' to install the missing dependencies."
          exit(1)
        end

        require(name)
      end
    end

  private

    class DependencyProxy

      def gem(name, version = nil)
        gems[name.to_s] = {version: version}
      end

      def each(&block)
        gems.each(&block)
      end

    private

      def gems
        @gems ||= {}
      end
    end

  end
end
