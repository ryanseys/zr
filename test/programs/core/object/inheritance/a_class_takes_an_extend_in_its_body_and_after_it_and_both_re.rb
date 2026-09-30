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

# A CLASS receiver, both spellings. `extend` in the body and a later
# `.extend` call put the module on the class's singleton chain -- an
# INSTANCE of the class is unaffected either way.
module Registry
  def registered = "registered #{self}"
end

class Widget
  extend Registry
end

class Gadget; end
Gadget.extend(Registry)

puts Widget.registered
puts Gadget.registered
p Widget.is_a?(Registry)
p Gadget.is_a?(Registry)
p Widget.singleton_class.ancestors.include?(Registry)
p Gadget.singleton_class.ancestors.include?(Registry)
p Widget.new.is_a?(Registry)
p Gadget.new.is_a?(Registry)

