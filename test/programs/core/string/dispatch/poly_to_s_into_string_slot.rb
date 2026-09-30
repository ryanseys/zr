# `to_s` on a receiver of unknown type, where a user class's `to_s` return is
# untyped, so the result type is only known at run time. The result lands in
# a String slot and must still read as that String.

class Cand
  attr_accessor :id

  def initialize(id)
    self.id = id
  end

  def to_s
    id
  end
end

class Req
  attr_accessor :verb
end

def build(v)
  r = Req.new
  r.verb = (v || "GET").to_s
  r
end

p build(nil).verb
p build("POST").verb
p Cand.new("z").to_s

# the same through a local rather than a writer
def label(v)
  s = (v || "none").to_s
  s
end
p label(nil)
p label("x")
p label(Cand.new("c"))

# and into an interpolation, where the slot is a string too
def show(v) = "[#{(v || 'd').to_s}]"
p show(nil)
p show("e")
