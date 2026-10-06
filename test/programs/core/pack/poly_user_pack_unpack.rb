# When the receiver can be an Array, a String or a user object, `pack` and
# `unpack1` call the user class's own method if it defines one.
class Frame
  def initialize
    @packed = 0
  end

  attr_reader :packed

  def pack(fmt)
    @packed += 1
    "frame:" + fmt
  end
end

class Wire
  def unpack1(fmt)
    "wire:" + fmt
  end
end

def packed(v) = v.pack("C*")
def first_of(v) = v.unpack1("C")

f = Frame.new
p packed(f)
p f.packed
p packed([65, 66])
p packed([1.5])

p first_of(Wire.new)
p first_of("AB")

# and with no user class in sight the plain calls work the same
p [65, 66].pack("C*")
p "AB".unpack1("C")
p "AB".unpack1("a")
