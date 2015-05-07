require_relative "../pipeline"

class Metacrunch::Pipeline::Configuration
  attr_accessor :processors

  def initialize(evalable_string)
    @processors = []
    instance_eval(evalable_string)
  end

  #
  # dsl methods
  #
  def processor(name, options = {})
    require name.underscore
    @processors << name.constantize.new(options)
  end

  alias_method :reader, :processor
  alias_method :writer, :processor
end
