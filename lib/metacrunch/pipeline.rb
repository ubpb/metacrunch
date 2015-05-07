require_relative "../metacrunch"

class Metacrunch::Pipeline
  require_relative "./pipeline/configuration"

  def initialize(options = {})
    @configuration = Configuration.new(
      File.read(
        resolve_file_path(options[:config_file_path])
      )
    )
  end

  def call
    until terminated?
      items = []

      @configuration.processors.each do |_processor|
        _processor.call(items, self) unless aborted?
      end
    end
  end

  alias_method :start, :call

  #
  # control flow api
  #
  def abort!
    @aborted = true
  end

  def aborted?
    !!@aborted
  end

  def terminate!
    @terminated = true
  end

  def terminated?
    !!@terminated
  end


  #
  private
  #
  def resolve_file_path(file_path)
    File.expand_path(File.join(Dir.pwd, file_path))
  end
end
