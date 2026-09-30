# frozen_string_literal: true

# Three forms that need no machinery of their own.
#
# `when *list` spreads its value the way a call site's splat does and tests
# the elements one at a time -- how MANY there are is a run-time number, so
# the arm is a loop where a written-out `when` is a chain.
#
# `def self.x` at the top level names `main`, which is one object and not a
# class, so the method lands on its singleton exactly as `def obj.x` does.
#
# A `super` in a scope with no `def` of its own may still BE a method at run
# time, and only the run time can tell.

SMALL = [1, 2, 3]
ROUND = [10, 20]

def kind(x)
  case x
  when *SMALL then :small
  when *ROUND then :round
  when 99 then :ninety_nine
  when *[] then :never
  else :other
  end
end
p [1, 3, 10, 20, 99, 7].map { |x| kind(x) }

# The elements are tested with `===`, so a class matches an instance.
case "abc"
when *[Integer, String] then puts "matched by class"
end

# `def self.x` at the top level.
def self.only_main = :from_main
p only_main
p self.only_main
p singleton_methods.sort
begin
  Object.new.only_main
rescue NoMethodError => e
  puts "NoMethodError: #{e.name}"
end

# A `super` in a top-level `def` walks above Object and finds nothing.
def no_parent
  super
rescue NoMethodError => e
  e.message
end
p no_parent

# A block that BECOMES a method at run time: an explicit-argument `super`
# reaches the target, and a bare one is ruby's own refusal.
class Base
  def who(*a) = "base#{a.inspect}"
end

explicit = Class.new(Base) { define_method(:who) { |*a| "dyn(" + super(*a) + ")" } }
p explicit.new.who(9)
p Class.new(Base) { define_method(:m) { defined?(super) ? "has" : "none" } }.new.m
p Class.new { define_method(:m) { defined?(super) ? "has" : "none" } }.new.m

bare = Class.new(Base) { define_method(:who) { super } }
begin
  bare.new.who
rescue RuntimeError => e
  puts "RuntimeError: #{e.message[0, 40]}"
end
