# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- full parameter shapes on a class method --------------------------------
class Sig
  def self.m(a, b = 2, *rest, k: 9, **kw, &blk)
    [a, b, rest, k, kw, blk ? blk.call : nil]
  end
end
p Sig.m(1)
p Sig.m(1, 3, 4, 5, k: 0, z: 1) { "blk" }

