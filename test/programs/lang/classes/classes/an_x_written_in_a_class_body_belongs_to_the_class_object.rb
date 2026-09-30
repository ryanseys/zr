# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- @x on the class object -------------------------------------------------
# A bare `@x = ...` in a class body seeds it; `def self.x` reads it.
class Registry
  @items = []
  @count = 0

  def self.add(x)
    @items << x
    @count += 1
    self          # so calls chain
  end

  def self.items = @items
  def self.count = @count
end

Registry.add("a").add("b").add("c")
p Registry.items
p Registry.count

# Reading one never written is nil -- no NameError (that's `@@x`'s rule, not
# this one).
class Quiet
  def self.probe = @never_written
end
p Quiet.probe

