# frozen_string_literal: true

module Metacrunch
  # Loads files that declare jobs, transforms and commands. Metacrunch.job,
  # Metacrunch.transform and Metacrunch.command register what they declare
  # with the load that is in progress on the current thread. A file is
  # loaded again only when it has changed, because loading it twice would
  # redefine its constants.
  module Loader

    KEY = :metacrunch_loading
    KINDS = {Job => "job", Transform => "transform", Command => "command"}.freeze

    @cache = {}

    module_function

    # How the command line selects one of several declarations of a file.
    SELECT_HINT = "select one with --job NAME"

    # The job, transform or command that path declares. name selects one of
    # several; kind (Job, Transform or Command) considers only those. hint
    # ends the message for a file that needs a selection.
    def load(path, name: nil, kind: nil, hint: SELECT_HINT)
      raise JobLoadError, "file not found: #{path}" unless File.file?(path)

      declarations = cached(path)
      declarations = declarations.grep(kind) if kind
      noun = kind ? KINDS.fetch(kind) : "job, transform or command"
      select_declaration(declarations, path, name&.to_s, noun, hint)
    end

    # What path declares, loaded again only when the file has changed.
    def cached(path)
      key = File.expand_path(path)
      mtime = File.mtime(key)
      cached_mtime, declarations = @cache[key]
      return declarations if cached_mtime == mtime

      declarations = collect(path)
      @cache[key] = [mtime, declarations]
      declarations
    end

    def register(declaration)
      Thread.current[KEY]&.push(declaration)
    end

    # Loads path now and returns what it declares, each with its file.
    def collect(path)
      previous = Thread.current[KEY]
      declarations = Thread.current[KEY] = []
      Kernel.load(File.expand_path(path))
      declarations.each { it.file = File.expand_path(path) }
    rescue ScriptError, StandardError => e
      raise JobLoadError, "could not load #{path}: #{e.class}: #{e.message}"
    ensure
      Thread.current[KEY] = previous
    end

    # Without name, the only declaration; or the only job or command, whose
    # building blocks the transforms beside it are.
    def select_declaration(declarations, path, name, noun, hint)
      raise JobLoadError, "no #{noun} defined in #{path}" if declarations.empty?
      return pick_named(declarations, path, name, noun) if name
      return declarations.first if declarations.one?

      runnable = declarations.grep_v(Transform)
      return runnable.first if runnable.one?

      raise JobLoadError, "#{path} defines several #{plural(declarations)} (#{names(declarations)}); #{hint}"
    end

    # The declaration named name. A name declared twice is refused, as in a
    # project, instead of taking the first; kind (see load) can make it
    # unique.
    def pick_named(declarations, path, name, noun)
      named = declarations.select { it.name == name }
      raise JobLoadError, "#{name} is declared more than once in #{path}; rename one" if named.size > 1

      named.first || raise(JobLoadError, "no #{noun} named #{name} in #{path} (available: #{names(declarations)})")
    end

    # "jobs", "jobs and commands" or "transforms, jobs and commands", in the
    # order of the file.
    def plural(declarations)
      words = declarations.map { "#{KINDS.fetch(it.class)}s" }.uniq
      [words[0...-1].join(", "), words.last].reject(&:empty?).join(" and ")
    end

    def names(declarations)
      declarations.map { it.name || "(unnamed)" }.join(", ")
    end

  end
end
