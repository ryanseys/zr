# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- `self` is the class object ---------------------------------------------
class Foo
  def self.who
    self
  end
end
p Foo.who
p Foo.who == Foo
p Foo.who.name
p Foo.who.new.class

