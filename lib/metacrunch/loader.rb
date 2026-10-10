# frozen_string_literal: true

module Metacrunch
  # Loads job files. Metacrunch.job registers each job with the load that
  # is in progress on the current thread. A file is loaded again only when
  # it has changed, because loading it twice would redefine its constants.
  module Loader

    KEY = :metacrunch_loading_jobs

    @cache = {}

    module_function

    def load(path, name: nil)
      raise JobLoadError, "job file not found: #{path}" unless File.file?(path)

      select_job(cached_jobs(path), path, name&.to_s)
    end

    def cached_jobs(path)
      key = File.expand_path(path)
      mtime = File.mtime(key)
      cached_mtime, jobs = @cache[key]
      return jobs if cached_mtime == mtime

      jobs = collect(path)
      @cache[key] = [mtime, jobs]
      jobs
    end

    def register(job)
      Thread.current[KEY]&.push(job)
    end

    def collect(path)
      previous = Thread.current[KEY]
      jobs = Thread.current[KEY] = []
      Kernel.load(File.expand_path(path))
      jobs
    rescue ScriptError, StandardError => e
      raise JobLoadError, "could not load #{path}: #{e.class}: #{e.message}"
    ensure
      Thread.current[KEY] = previous
    end

    def select_job(jobs, path, name)
      raise JobLoadError, "no job defined in #{path}" if jobs.empty?
      return pick_named(jobs, path, name) if name
      return jobs.first if jobs.one?

      raise JobLoadError, "#{path} defines several jobs (#{names(jobs)}); select one with --job NAME"
    end

    def pick_named(jobs, path, name)
      jobs.find { |job| job.name == name } ||
        raise(JobLoadError, "no job named #{name} in #{path} (available: #{names(jobs)})")
    end

    def names(jobs)
      jobs.map { |job| job.name || "(unnamed)" }.join(", ")
    end

  end
end
