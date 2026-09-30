# Top-level `include <Mod>` mixes the module's module_function
# methods into the main scope so bare `<m>` calls dispatch to
# them. CRuby installs them on Object.

module Greeter
  module_function

  def hello(name)
    "hello, " + name + "!"
  end

  def bye
    "bye"
  end
end

include Greeter

# ---
# `include Outer::Inner` (ConstantPathNode arg) at top level.

module Outer
  module Inner
    module_function

    def greet
      "hi-from-Outer-Inner"
    end
  end
end

include Outer::Inner

puts greet

