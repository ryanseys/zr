# `extend` changes what a receiver IS, not only what it answers: the module
# joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
# a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
# receiver's class -- and every other instance of it -- stay untouched.

module Greet
  def greet = "hey #{name}"
end

module Tagged; end

module Nested
  include Tagged
end

class Person
  def initialize(name) = @name = name
  def name = @name
end

a = Person.new("a")
b = Person.new("b")
a.extend(Greet)

# Two extends layer, newest closest to the singleton, and a repeat is a no-op.
module First
  def which = "first"
end
module Second
  def which = "second"
end
layered = Person.new("l")
layered.extend(First)
layered.extend(Second)
layered.extend(First)
puts layered.which
p layered.is_a?(First)
p layered.is_a?(Second)
p layered.singleton_class.ancestors.take(3).drop(1)

