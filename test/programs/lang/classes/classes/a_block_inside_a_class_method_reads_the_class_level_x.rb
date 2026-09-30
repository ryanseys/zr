# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- class-level @x from inside a block -------------------------------------
# The block captures `self` as the class object, so the ivar has to resolve
# to the same storage the direct path uses.
class Collect
  @seen = []
  def self.run
    [1, 2, 3].each { |i| @seen << i * 10 }
    @seen
  end
end
p Collect.run

