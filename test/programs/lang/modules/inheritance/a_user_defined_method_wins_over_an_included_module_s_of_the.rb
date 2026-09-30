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
# A user-defined top-level `def` is not shadowed by a later
# `include` of a module with the same method name. CRuby's
# method-lookup places user defs above the include chain.

module Tail
  module_function

  def kept_for_user
    "from-Tail"
  end

  def tail_only
    "tail-only"
  end
end

def kept_for_user
  "user-defined"
end

include Tail

puts kept_for_user   # user-defined wins
puts tail_only       # still resolvable
