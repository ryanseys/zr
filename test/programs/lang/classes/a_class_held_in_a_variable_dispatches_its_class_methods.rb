# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- dispatching over a class held in a variable ----------------------------
# The receiver isn't a literal constant here, so this can't be a direct call
# -- it dispatches on the class value at runtime.
class HandlerA
  def self.run(x) = "A:#{x}"
end
class HandlerB
  def self.run(x) = "B:#{x}"
end

[HandlerA, HandlerB].each { |h| puts h.run(1) }

current = HandlerA
puts current.run(2)
current = HandlerB
puts current.run(2)

