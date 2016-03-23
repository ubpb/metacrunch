require_relative "../transformator"

class Metacrunch::Transformator::Transformation
  require_relative "./transformation/step"

  attr_accessor :source
  attr_accessor :target

  class << self
    def steps(value = nil)
      unless value
        @steps
      else
        @steps = value
      end
    end
    alias_method :sequence, :steps
  end

  def self.call(*args)
    new.call(*args)
  end

  # since a transformation can have many steps, writing a "require" for each is tedious
  def self.require_directory(directory)
    Dir.glob("#{File.expand_path(directory)}/*.rb").each do |_filename|
      require _filename
    end
  end

  def initialize
    # steps are instanced once, which means that instance variables retain
    @steps = self.class.steps.flatten.map do |_step|
      _step.is_a?(Class) ? _step.new(self) : _step
    end
  end

  def call(source, options = {})
    @source = source
    @target = options[:target]

    @steps.each do |_step|
      _step.is_a?(Proc) ? instance_exec(&_step) : _step.call
    end

    return @target
  end
end
