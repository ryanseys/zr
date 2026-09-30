# A setter call (`obj.x = val`) on a parameter that can hold objects
# of more than one class must execute the assignment.
#
# Three subcases:
#  1. Single class with `x`, second class without.
#  2. Two classes share an ivar name; same value type.
#  3. Two classes share an ivar name; differing value types
#     (string vs int).
#
# The example checks the *side effect* (the ivar's value), not the
# return value of the setter expression.

# --- 1. Single class ----------------------------------------------------

class Foo
  attr_accessor :x
  def initialize; @x = 0; end
end

class Bar
  # No `x`; coexists only to widen `obj` to a class union.
end

def set_x(obj, v)
  obj.x = v
end

foo = Foo.new
bar = Bar.new
set_x(foo, 42)
set_x(bar, 99) rescue nil

puts foo.x


# --- 2. Two classes share `body` (string in both) ---------------------

class Req
  attr_accessor :body
  def initialize; @body = ""; end
end

class Res
  attr_accessor :body
  def initialize; @body = ""; end
end

def set_body(o, b)
  o.body = b
end

req = Req.new
res = Res.new
set_body(req, "REQ")
set_body(res, "RES")

puts req.body
puts res.body


# --- 3. Two classes share `slot` with *different* value types ---------
# Each setter stores the value with its own type.

class IBox
  attr_accessor :slot
  def initialize; @slot = 0; end
end

class SBox
  attr_accessor :slot
  def initialize; @slot = ""; end
end

def set_slot(o, v)
  o.slot = v
end

ibox = IBox.new
sbox = SBox.new
set_slot(ibox, 7)
set_slot(sbox, "hello")

puts ibox.slot
puts sbox.slot
