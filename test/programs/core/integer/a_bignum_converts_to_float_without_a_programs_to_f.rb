# A Bignum converts to a Float natively, so a program's Integer#to_f
# that converts a Bignum itself does not run again inside the
# conversion.
Integer.class_eval do
  alias_method :_to_f, :to_f
  def to_f = (self << 1)._to_f
end
p Math.cos(1 << 64) == Math.cos((1 << 64 << 1)._to_f)
p Math.log(1 << 64) == Math.log((1 << 64 << 1)._to_f)
p (1 << 64)._to_f
