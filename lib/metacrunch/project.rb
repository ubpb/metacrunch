# frozen_string_literal: true

module Metacrunch
  # A project: the directory of a Metacrunchfile, and the jobs, transforms
  # and commands its files declare (see the Readme, "Projects and
  # commands"). A name declared more than once stays in the project, but
  # fetch refuses it and duplicates lists it; a file that fails to load is
  # kept in load_errors.
  class Project

    FILE = "Metacrunchfile"
    KEY = :metacrunch_loading_project

    attr_reader :file, :root, :load_errors

    # The nearest Metacrunchfile at or above dir, or nil.
    def self.find(dir)
      current = File.expand_path(dir)
      loop do
        candidate = File.join(current, FILE)
        return candidate if File.file?(candidate)

        parent = File.dirname(current)
        return if parent == current

        current = parent
      end
    end

    # The project of the nearest Metacrunchfile at or above dir. Raises
    # ProjectError if there is none or it fails to load.
    def self.load(dir = Dir.pwd)
      file = find(dir) || raise(ProjectError, "no #{FILE} found in #{File.expand_path(dir)} or above")
      load_file(file)
    end

    # The project of the nearest Metacrunchfile at or above dir, or nil if
    # there is none. Raises ProjectError if it fails to load.
    def self.nearest(dir = Dir.pwd)
      file = find(dir)
      file && load_file(file)
    end

    # Loads file, a Metacrunchfile, with the files it loads. Raises
    # ProjectError if the Metacrunchfile itself fails.
    def self.load_file(file) = new(file)

    # The project whose Metacrunchfile is being loaded on this thread.
    def self.loading = Thread.current[KEY]

    private_class_method :new

    def initialize(file)
      @file = File.expand_path(file)
      @root = Pathname(File.dirname(@file))
      @declarations = {}
      @files = [@file]
      @load_errors = []
      load_metacrunchfile
    end

    # The declared names, sorted; duplicates included.
    def names = @declarations.keys.sort

    def include?(name) = @declarations.key?(name.to_s)

    # The jobs, transforms and commands declared as name: one, several for a
    # duplicate, or none.
    def declared(name) = @declarations.fetch(name.to_s, [])

    # The Job, Transform or Command named name. Raises ProjectError if the
    # name is unknown or declared more than once.
    def fetch(name)
      declarations = declared(name)
      raise ProjectError, "unknown job, transform or command: #{name}#{load_hint}" if declarations.empty?
      return declarations.first if declarations.one?

      raise ProjectError, duplicate_message(name)
    end

    # The names declared more than once, sorted, each with the files that
    # declare it (relative to the root). Such a name cannot be used until
    # one is renamed; a test of the project can check that there is none.
    def duplicates
      @declarations.select { |_name, declarations| declarations.size > 1 }.sort.to_h do |name, declarations|
        [name, declarations.map { relative(it.file) }]
      end
    end

    # "x is declared more than once (jobs/x.rb, transforms/x.rb); rename one"
    def duplicate_message(name)
      "#{name} is declared more than once (#{declared(name).map { relative(it.file) }.join(", ")}); rename one"
    end

    # Runs a job, transform or command of the project like invoke in a
    # command body (see Invoker#invoke), with its own streams, environment
    # and logger.
    def invoke(target, *argv, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout, workers: nil,
               limit: nil)
      Invoker.new(project: self, logger:, env:, stdin:, stdout:).invoke(target, *argv, workers:, limit:)
    end

    # Loads the files that match globs (relative to the root, or absolute),
    # in sorted order and each once. A file that fails or declares a
    # reserved name contributes nothing and ends up in load_errors.
    def load_files(globs)
      paths = globs.flatten.flat_map { matches(it.to_s) }
      paths.select { File.file?(it) }.map { File.expand_path(it) }.uniq.sort.each { add_file(it) }
      nil
    end

    # path relative to the root if it is below it, else path.
    def relative(path)
      prefix = "#{@root}/"
      path.start_with?(prefix) ? path.delete_prefix(prefix) : path
    end

    # One line about a file that did not load, with paths relative to the
    # root: "jobs/x.rb: SyntaxError: jobs/x.rb:3: syntax error found".
    def load_error_summary(file, error)
      line = error.message.lines.first.to_s.chomp.gsub(file, relative(file))
      "#{relative(file)}: #{error.class}: #{line}"
    end

    # " (2 files of the project did not load)", or "" if all loaded.
    def load_hint
      count = @load_errors.size
      return "" if count.zero?

      " (#{count} #{count == 1 ? "file" : "files"} of the project did not load)"
    end

    def inspect = "#<#{self.class.name} #{@file}>"

    private

    def load_metacrunchfile
      add_all(loading(self) { Loader.collect(@file) })
    rescue JobLoadError => e
      raise ProjectError, e.message
    end

    # Metacrunch.load_files works while the Metacrunchfile loads, not in
    # the files it loads.
    def loading(project)
      previous = Thread.current[KEY]
      Thread.current[KEY] = project
      yield
    ensure
      Thread.current[KEY] = previous
    end

    def add_file(path)
      return if @files.include?(path)

      @files << path
      add_all(loading(nil) { Loader.cached(path) })
    rescue JobLoadError => e
      @load_errors << [path, e.cause || e]
    rescue ProjectError => e
      @load_errors << [path, e]
    end

    # Adds what one file declares, or nothing if it uses a reserved name.
    def add_all(declarations)
      reserved = declarations.find { Names.reserved?(it.name) }
      raise ProjectError, "the name #{reserved.name} is reserved for a built-in command" if reserved

      declarations.each { add(it) }
    end

    # Unnamed jobs have no name in the project; they run by path only.
    def add(declaration)
      return unless declaration.name

      (@declarations[declaration.name] ||= []) << declaration
    end

    # Relative globs are expanded below the root, absolute ones below their
    # longest leading directory that exists, so that characters such as [
    # in the path of that directory do not count as a pattern.
    def matches(glob)
      base, pattern = File.absolute_path?(glob) ? split_absolute(glob) : [@root.to_s, glob]
      Dir.glob(pattern, base:).map { File.join(base, it) }
    end

    # [directory, pattern] for an absolute glob.
    def split_absolute(glob)
      parts = glob.split("/")
      count = (parts.size - 1).downto(2).find { File.directory?(parts.first(it).join("/")) } || 1
      [count == 1 ? "/" : parts.first(count).join("/"), parts.drop(count).join("/")]
    end

  end
end
