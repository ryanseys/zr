# Class-level state: `self` inside a class method, and the instance
# variables of the CLASS OBJECT itself.
#
# The one rule everything here follows from: in a class method (or a class
# body), `self` is the class object. So `@x` there is that object's own ivar
# -- a different thing from both `@@x` and an instance's `@x` -- and an
# implicit-self call is a send to whichever class was actually called.

# --- reflection over a class object's ivars ---------------------------------
class Reflect
  @a = 1
end
p Reflect.instance_variable_get(:@a)
p Reflect.instance_variable_get("@a")     # a String name works too
p Reflect.instance_variable_get(:@absent) # nil, not an error
p Reflect.instance_variable_set(:@b, 2)   # answers the VALUE
p Reflect.instance_variables
p Reflect.instance_variable_defined?(:@a)
p Reflect.instance_variable_defined?(:@absent)

begin
  Reflect.instance_variable_get(:a)       # no leading @
rescue NameError => e
  puts "NameError: #{e.message}"
end
