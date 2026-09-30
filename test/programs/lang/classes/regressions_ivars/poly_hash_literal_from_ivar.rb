# A method returns `{ key: @x, ... }`, where one writer sets `@x` to
# an Integer and another sets it to a String. The Hash literal holds
# the ivar value, whatever its class.

class T_poly_hash_literal_from_ivar_C
  def initialize
    @x = 0
  end
  def write_str(s)
    @x = s
  end
  def hash_of_x
    { key: @x }
  end
end

c = T_poly_hash_literal_from_ivar_C.new
c.write_str("hello")
puts c.hash_of_x.size       # 1
puts c.hash_of_x.has_key?(:key)  # true

# Multiple sym-keyed entries, all from ivars of mixed classes.
class T_poly_hash_literal_from_ivar_D
  def initialize
    @a = 0
    @b = 0
  end
  def write(sa, sb)
    @a = sa
    @b = sb
  end
  def attrs
    { a: @a, b: @b }
  end
end

d = T_poly_hash_literal_from_ivar_D.new
d.write("alpha", "beta")
puts d.attrs.size           # 2
puts d.attrs.has_key?(:a)   # true
puts d.attrs.has_key?(:c)   # false
