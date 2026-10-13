# ruby 4.1 no longer rewrites the cref of a cloned class's or module's
# methods (88095eb196, Feature #21981): a method that the original
# defined reads the original's constants and class variables, wherever
# the copy is. A method that the copy's own body defines reads the copy's.
class CloneTest
  TEST = :C0
  def foo = TEST
end
CloneTest1 = CloneTest.clone
class CloneTest1
  remove_const(:TEST)
  TEST = :C1
  def own = TEST
end
p CloneTest1.new.foo, CloneTest1.new.own, CloneTest1::TEST

module CloneTestM0
  TEST = :M0
  def foo = TEST
end
CloneTestM1 = CloneTestM0.clone
module CloneTestM1
  remove_const(:TEST)
  TEST = :M1
end
class CloneTestC1
  include CloneTestM1
end
p CloneTestC1.new.foo

# A constant that only the copy has is not found.
class Lonely
  def find = ONLY_IN_COPY
end
L2 = Lonely.dup
class L2
  ONLY_IN_COPY = 1
end
p((L2.new.find rescue $!.class))

# Class variables resolve through the original too.
class CvarA
  @@a = "A"
  def a = @@a

  def a=(v)
    @@a = v
  end
end
CvarB = CvarA.dup
CvarB.new.a = "B"
p CvarA.new.a, CvarB.new.a, CvarB.class_variable_get(:@@a)

class Gods
  @@rule = "Uranus"
  def ruler0 = @@rule
end
Zeus = Gods.clone
class Zeus
  def ruler5 = @@rule
end
Zeus.class_variable_set(:@@rule, "Athena")
p Gods.new.ruler0, Zeus.new.ruler0, Zeus.new.ruler5, Zeus.class_variable_get(:@@rule)

# Singleton methods of the original read the original's constants.
module WithSelf
  C = 1
  def self.m = C
end
m = WithSelf.clone
p m::C, m.m
