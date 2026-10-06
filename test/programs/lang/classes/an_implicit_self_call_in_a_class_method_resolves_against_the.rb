# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- an implicit-self call resolves against the RECEIVER --------------------
# `new` and `name` below are sends to `self`, and `self` is whichever class
# was called -- not the one whose body the method was written in.
class Shape
  def self.build = new
  def self.label = "a #{name}"
end
class Circle < Shape; end

p Shape.build.class
p Circle.build.class               # Circle, not Shape
p Circle.label

module Greeter
  def greet = "hello from #{name}"
end
class English
  extend Greeter
end
p English.greet                    # names English, not Greeter

