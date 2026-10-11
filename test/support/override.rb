# frozen_string_literal: true

# Replaces a singleton method while a block runs (Minitest 6 has no stub).
module Override

  def override(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end

end
