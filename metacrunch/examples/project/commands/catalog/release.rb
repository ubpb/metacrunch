# frozen_string_literal: true

require "fileutils"

# Writes a new release of the catalog into out/releases/TIME/ and points
# out/current at it, but only if the job ended :ok: readers of out/current
# never see a half-written or failed release. The switch renames a
# symbolic link, so it is atomic.
#
#   cd examples/project
#   bundle exec metacrunch run catalog:release
#   bundle exec metacrunch run catalog:release --input data/broken.jsonl    # exit status 3, out/current stays
Metacrunch.command "catalog:release", desc: "Write a new release and switch out/current to it" do
  params do
    param :input, String, desc: "JSON Lines with title records (default: the job's)"
    param :out, String, desc: "Directory for releases/ and current (default: out/ in the project)"
  end

  run do
    out = params.out ? Pathname(params.out) : root.join("out")
    release = out.join("releases", Time.now.strftime("%Y%m%d-%H%M%S-%L"))
    FileUtils.mkdir_p(release)
    result = invoke "catalog", params: {output: release, input: params.input}
    next logger.warn("catalog:release: #{result.status}; out/current not switched") unless result.ok?

    # A new link renamed over the old one: the switch is atomic.
    link = out.join("current.new")
    FileUtils.rm_f(link)
    File.symlink(release.relative_path_from(out), link)
    File.rename(link, out.join("current"))
    logger.info("catalog:release: out/current is #{release.relative_path_from(out)}")
    release
  end
end
