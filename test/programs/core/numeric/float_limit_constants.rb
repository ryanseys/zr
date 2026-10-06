# Float::MAX / MIN / EPSILON are the limits of a double.
# Integer has no public constants in CRuby (it is arbitrary
# precision), so Integer::MAX must raise NameError.
puts Float::MAX
puts Float::MIN
puts Float::EPSILON
puts(Float::MAX > Float::MIN)
puts((1.0 + Float::EPSILON) > 1.0)
imax = Integer::MAX rescue "NameError"
puts imax
imin = Integer::MIN rescue "NameError"
puts imin
