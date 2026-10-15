# Integer#size is a word for a fixnum and the bytes of a bignum's
# magnitude, so a negative bignum counts as its absolute value does.
[
  0, 7, -1, 2**62 - 1, -(2**62),
  2**62, -(2**62) - 1, 2**63 - 1, 2**63, -(2**63), -(2**63) - 1,
  2**64 - 1, 2**64, -(2**64), -(2**64) + 1, -(2**64) - 1,
  2**100, -(2**100), 2**128, -(2**128), 2**200, -(2**200) - 1,
].each { |n| puts "#{n}: #{n.size}" }

values = [2**64, 1, -(2**64), 2**70 - 2**70, -(2**128)]
p values.map(&:size)
p (2**70 - (2**70 - 7)).size, (-(2**70) + 2**70 - 3).size
