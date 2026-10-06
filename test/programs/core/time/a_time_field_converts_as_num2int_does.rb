# A field of Time.gm converts as NUM2INT does: outside long is the
# bignum error, outside int names the integer, and a negative int is out
# of range.
[2**31, 2**40, 2**62, 2**64, 10_000_000_000_000_000_001.0, -(2**31), -(2**33), -1, 61].each do |v|
  Time.gm(2000, 1, 1, 0, 0, v)
rescue RangeError, ArgumentError => e
  p [v, e.class, e.message]
end
