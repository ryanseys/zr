# `prepend M` inside `class << self` DISPATCHES correctly -- M's instance
# methods shadow the class's own `def self.x`, and `super` reaches the
# original. Only reflection disagrees: the module is absent from
# `singleton_class.ancestors`.
#
# It was expected to fall out of the singleton-surrogate work, and it did not.
# The prepended module is a compile-time input to the method resolution
# order that nothing carries into the runtime's ancestor registry. Making
# the ancestry right means registering the module in its ancestors too.
module Loud
  def greet = "LOUD " + super
end
class Speaker
  class << self
    prepend Loud
  end
  def self.greet = "hi"
end

# Dispatch: right.
p Speaker.greet

# Reflection: wrong.
p Speaker.singleton_class.ancestors.include?(Loud)
p Speaker.singleton_class.ancestors.first
p Speaker.singleton_class.include?(Loud)
