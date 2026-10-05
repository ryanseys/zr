# A Float compares exactly with -2**62, the smallest Fixnum; 1 and -1 stay
# Integers under a negative exponent; and round(half:) refuses a name in
# a wide encoding (test_float.rb, test_fixnum.rb).
a = -(1 << 62)
b = -4611686018427387904
f = a.to_f
p [a == b, f == a, a == f, f <=> a, a <=> f, f == b, f <=> b, f > a - 1, f < a + 1]
p [f.floor == a, f.floor <= f, f.to_i == a]
c = 1 << 62
g = c.to_f
p [g == c, g <=> c, g == c - 1, (g <=> c + 1)]
big = 1 << 66
p [1 ** -big, (-1) ** -big, (-1) ** -(big + 1)]
p [1 ** -big, (-1) ** -big].map(&:class)
bad = []
100.times do |i|
  int0 = 1 << i
  [int0, -int0].each do |int|
    flt = int.to_f
    checks = [flt == int, flt > int - 1, flt >= int - 1, flt < int + 1, flt <= int + 1, (flt <=> int) == 0, (flt <=> int + 1) == -1, (flt <=> int - 1) == 1]
    bad << [i, int.negative?, checks] unless checks.all?
  end
end
p bad.first(4), bad.size
f = -4611686018427387904.0
i = f.floor
p [i, i <= f, f - i, i.class]
begin
  1.0.round(half: "up".encode("utf-16be"))
rescue => e
  p [e.class, e.message]
end
p Float("0x1p+0") rescue p $!
