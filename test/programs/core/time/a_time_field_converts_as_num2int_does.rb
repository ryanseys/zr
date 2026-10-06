# A field of Time.gm converts as NUM2INT does: outside long is the
# bignum error, outside int names the integer, and a negative int is out
# of range. The seconds read as an exact number.
[2**31, 2**40, 2**62, 2**64, 10_000_000_000_000_000_001.0, -(2**31), -(2**33), -1, 61].each do |v|
  Time.gm(2000, 1, 1, 0, 0, v)
rescue RangeError, ArgumentError => e
  p [v, e.class, e.message]
end
# The seconds read as an exact number: to_r, which needs to_int as well.
o = Object.new
def o.to_int = 0
def o.to_r = nil
p((Time.gm(2000, 1, 1, 0, 0, o) rescue [$!.class, $!.message]))
def o.to_r = Rational(3, 2)
t = Time.gm(2000, 1, 1, 0, 0, o)
p [t.sec, t.subsec]
q = Object.new
def q.to_int = 5
p Time.gm(2000, 1, 1, 0, 0, q).sec
p((Time.gm(2000, 1, 1, 0, 0, Object.new) rescue [$!.class, $!.message]))
