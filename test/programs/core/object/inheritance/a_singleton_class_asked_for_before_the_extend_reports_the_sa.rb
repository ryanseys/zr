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

# A singleton class asked for BEFORE the extend reports the same chain as one
# asked for after -- it is one class, not two.
late = Person.new("late")
sc = late.singleton_class
late.extend(Greet)
p sc.equal?(late.singleton_class)
p sc.ancestors.include?(Greet)

