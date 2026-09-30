# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- module-level state -----------------------------------------------------
module Counter
  @n = 0
  def self.bump = @n += 1
  def self.n = @n
end
Counter.bump
Counter.bump
p Counter.n

