require_relative "../transformation"

class Metacrunch::Transformator::Transformation::Step
  attr_accessor :transformation

  def initialize(transformation = nil, options = {})
    if transformation.is_a?(Hash)
      options = transformation
      transformation = nil
    end

    if transformation
      @transformation = transformation
    else
      @transformation = Struct.new(:source, :target).new.tap do |_struct|
        _struct.source = options[:source]
        _struct.target = options[:target]
      end
    end
  end

  def call
  end

  #
  # Each step has transparent access to all methods of it's transformation
  #
  def method_missing(method_name, *args, &block)
    if @transformation.respond_to?(method_name)
      @transformation.send(method_name, *args, &block)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    @transformation.respond_to?(method_name) || super
  end

  # avoid method_missing penalty for the most used transformation methods
  def source;         @transformation.source;         end
  def source=(value); @transformation.source=(value); end
  def target;         @transformation.target;         end
  def target=(value); @transformation.target=(value); end
end
