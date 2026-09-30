# User-defined | & ^ % call the method of the class, not a raw
# bitwise or modulo operation.
class Flags
  def initialize(v)
    @v = v
  end
  def |(o)
    @v + 100
  end
  def &(o)
    @v + 200
  end
  def ^(o)
    @v + 300
  end
  def %(o)
    @v + 400
  end
end
f = Flags.new(1)
g = Flags.new(2)
puts(f | g)
puts(f & g)
puts(f ^ g)
puts(f % g)
# Builtin Integer operators also work.
puts(6 | 1)
puts(6 & 4)
puts(6 ^ 2)
puts(7 % 3)
