# Math converts an Integer with the program's Integer#to_f once one
# replaces ruby's, as rb_to_float does, and counts a wide Bignum's
# doublings without it.
def check(a, b) = p((a - b).abs <= 1e-12)
check(Math.log(1 << 2000), 2000 * Math.log(2))
Integer.class_eval do
  alias_method :_to_f, :to_f
  def to_f = (self + 1)._to_f
end
check(Math.cos(1.0), Math.cos(0))
check(Math.exp(1.0), Math.exp(0))
check(Math.log(1.0), Math.log(0))
check(Math.sqrt(4.0), Math.sqrt(3))
Integer.class_eval do
  remove_method :to_f
  alias_method :to_f, :_to_f
end
p Math.cos(0)
