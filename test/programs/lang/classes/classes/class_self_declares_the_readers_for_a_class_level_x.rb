# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- `class << self` -- the idiomatic declaration ---------------------------
# `attr_accessor` there generates `def self.handler; @handler; end`, so it is
# class-level ivars all the way down.
module Plugin
  class << self
    attr_accessor :handler
    attr_reader :registered

    def register(h)
      @registered ||= []
      @registered << h
      self.handler = h
    end
  end
end

Plugin.register("first")
Plugin.register("second")
p Plugin.handler
p Plugin.registered

