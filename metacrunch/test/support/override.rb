# frozen_string_literal: true

# Replaces a singleton method while a block runs (Minitest 6 has no stub).
module Override

  def override(object, name, implementation)
    original = object.method(name)
    replace_method(object, name, implementation)
    yield
  ensure
    replace_method(object, name, original) if original
  end

  private

  # Removes the method first, so Ruby does not warn about redefining it.
  def replace_method(object, name, body)
    singleton = object.singleton_class
    singleton.remove_method(name) if singleton.method_defined?(name, false)
    object.define_singleton_method(name, body)
  end

end
