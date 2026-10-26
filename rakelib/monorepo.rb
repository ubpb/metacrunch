# frozen_string_literal: true

require "bundler"

# The gems of this repository and their shared version (see the root Readme).
module Monorepo

  class Error < StandardError; end

  CORE = "metacrunch"
  VERSION_LINE = /^(\s*)VERSION = "[^"]*"$/

  module_function

  # The directories under root that hold a gemspec of their own name, core first, the others by name.
  def gems(root = Dir.pwd)
    names = Dir.children(root).select { File.file?(File.join(root, it, "#{it}.gemspec")) }
    names.sort_by { [it == CORE ? 0 : 1, it] }
  end

  # metacrunch: lib/metacrunch/version.rb; metacrunch-csv: lib/metacrunch/csv/version.rb
  def version_file(root, gem)
    File.join(root, gem, "lib", *gem.split("-"), "version.rb")
  end

  # Writes version into the version.rb of every gem, then calls lock with each gem's directory. Checks every
  # file before it writes one.
  def set_version(version, root: Dir.pwd, lock: method(:bundle_lock))
    raise ArgumentError, "not a version: #{version.inspect}" unless canonical?(version)

    texts = gems(root).to_h { [it, version_text(root, it)] }
    texts.each do |gem, text|
      File.write(version_file(root, gem), text.sub(VERSION_LINE, "\\1VERSION = \"#{version}\""))
    end
    texts.each_key { lock.call(File.join(root, it)) }
  end

  def canonical?(version)
    version.is_a?(String) && Gem::Version.correct?(version) && Gem::Version.new(version).to_s == version
  end

  def version_text(root, gem)
    path = version_file(root, gem)
    name = path.delete_prefix("#{root}/")
    raise Error, "#{name}: no such file" unless File.file?(path)

    text = File.read(path)
    count = text.scan(VERSION_LINE).size
    raise Error, "#{name}: expected one VERSION line, found #{count}" unless count == 1

    text
  end

  def bundle_lock(dir)
    locked = Bundler.with_unbundled_env { system("bundle", "lock", chdir: dir) }
    raise Error, "bundle lock failed in #{File.basename(dir)}" unless locked
  end

end
