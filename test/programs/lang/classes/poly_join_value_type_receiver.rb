# `v.join(", ")` on a value of unknown type calls the user class's own
# `join` when v is a P, and Array#join when v is an Array.
#
# Nothing here passes a P to `show`: a small class with no mutator is
# a special case, and the example must keep P that way.

class P
  def initialize(b)
    @b = b
  end

  def join(part)
    P.new(@b + "/" + part)
  end

  def to_s
    @b
  end
end

def show(v)
  v.join(", ")
end

puts show([1, 2])
puts show(["a", "b"])
puts P.new("x").join("y").to_s
