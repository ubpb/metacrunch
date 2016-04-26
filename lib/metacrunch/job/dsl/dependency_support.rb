require "rubygems/dependency_installer"

module Metacrunch
  class Job::Dsl::DependencySupport

    def initialize(install: false, &block)
      proxy = DependencyProxy.new
      proxy.instance_eval(&block)

      if install
        installer = Gem::DependencyInstaller.new
        puts "Installing dependencies..."
        proxy.each do |name, options|
          args = [name, options[:version]].compact
          installer.install(*args)
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
          puts "'#{e.name}' (#{e.requirement}) is not installed. Use 'metacrunch run JOB_FILE --install' to install required dependencies."
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
