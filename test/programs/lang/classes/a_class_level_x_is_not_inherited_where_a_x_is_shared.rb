# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- NOT inherited (the difference from @@x) --------------------------------
# A subclass inherits the METHOD but gets its own, empty storage. A class
# variable, by contrast, is genuinely shared.
class Base
  @tag = "base"
  @@shared = "shared"
  def self.tag = @tag
  def self.tag=(v)
    @tag = v
  end
  def self.shared = @@shared
end
class Sub < Base; end

p [Base.tag, Sub.tag]              # Sub's slot is empty...
p [Base.shared, Sub.shared]        # ...but the cvar is one slot, shared
Sub.tag = "sub"
p [Base.tag, Sub.tag]              # writes stay independent

