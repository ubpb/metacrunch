require "etc"
require "net/scp"
require "net/ssh"
require "securerandom"
require_relative "../reader"

class Metacrunch::File::Reader::ScpFetcher
  include Enumerable

  RECOGNIZED_PROTOCOL_REGEX = /\Ascp:\/\//
  TILDE_REPLACEMENT = "/__TILDE__"

  def self.accepts?(url)
    !!url[RECOGNIZED_PROTOCOL_REGEX]
  end

  def initialize(url, options = {})
    URI(url.sub("~", TILDE_REPLACEMENT)).try do |_uri|
      @host = _uri.host
      @password = options[:password] || _uri.password
      @path = _uri.path.sub(TILDE_REPLACEMENT, "~")
      @username = options[:username] || _uri.user || Etc.getlogin
    end
  end

  def each
    return enum_for(__method__) unless block_given?

    begin
      begin
        Dir.mkdir temporary_directory = File.join(Dir.tmpdir, SecureRandom.hex)
      rescue Errno::EEXIST
        retry
      end

      remote_filenames.each do |_remote_filename|
        _local_filename = File.join(temporary_directory, File.basename(_remote_filename))
        Net::SCP.download!(@host, @username, _remote_filename, _local_filename, ssh: { password: @password })
        yield _local_filename
        File.delete(_local_filename)
      end
    ensure
      FileUtils.remove_dir(temporary_directory)
    end
  end

  private

  def remote_filenames
    @remote_filenames ||= [].tap do |_remote_filenames|
      Net::SSH.start(@host, @username, password: @password) do |_ssh|
        _remote_filenames.concat _ssh.exec!("ruby -e \"puts Dir.glob(File.expand_path('#{@path}'))\"").try(:split, "\n") || []
      end
    end
  end
end
