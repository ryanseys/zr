# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- a class @x and an instance @x are different slots ----------------------
# `def self.x` and `def x` are two namespaces in Ruby, and their `@x`s name
# two different objects' storage.
class Dual
  @x = "class-level"
  def initialize
    @x = "instance-level"
  end
  def self.x = @x
  def x = @x
end
p [Dual.x, Dual.new.x]

