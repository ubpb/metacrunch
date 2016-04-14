module Metacrunch
  class Job::Dsl::BundlerSupport

    #
    # This is a customization of bundler/inline for use with metacrunch jobs.
    # @see https://github.com/bundler/bundler/blob/master/lib/bundler/inline.rb
    #
    def initialize(install: false, &gemfile)
      old_root = Bundler.method(:root)
      def Bundler.root
        Bundler::SharedHelpers.pwd.expand_path
      end
      ENV["BUNDLE_GEMFILE"] ||= "Gemfile"

      builder = Bundler::Dsl.new
      builder.instance_eval(&gemfile)
      definition = builder.to_definition(nil, true)

      #
      # In case this method is called in a context where Bundler is already active
      # (e.g. when metacrunch CLI is called with bundle exec), we merge the dependencies
      # of the metacrunch gem with the ones defined in the job.
      #
      begin
        org_definition = Bundler.definition
        if org_definition
          definition = Bundler::Definition.new(
            nil,
            org_definition.instance_variable_get("@dependencies") + definition.instance_variable_get("@dependencies"),
            org_definition.instance_variable_get("@sources"),
            true
          )
        end
      rescue Bundler::GemfileNotFound
        # This is called in cases where no Bundler context is available,
        # when calling Bundler.definition.
        # I'm sure there is a better way to check this, but I don't know how.
      end

      def definition.lock(*); end
      definition.validate_ruby!

      if install
        Bundler.ui = Bundler::UI::Shell.new
        Bundler::Installer.install(Bundler.root, definition, :system => true)
        Bundler::Installer.post_install_messages.each do |name, message|
          Bundler.ui.info "Post-install message from #{name}:\n#{message}"
        end
      end

      runtime = Bundler::Runtime.new(nil, definition)
      runtime.setup.require

      bundler_module = class << Bundler; self; end
      bundler_module.send(:define_method, :root, old_root)
    end

  end
end
