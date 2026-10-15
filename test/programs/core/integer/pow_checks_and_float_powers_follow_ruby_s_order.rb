# Integer#** of a Float answers a zero exponent, a base of 0 and a base of
# 1 before C's pow, so 0 ** NaN is 0.0. Integer#pow(b, m) checks b's type,
# b's sign, then m's type, and answers 0**b before it reads a zero m.
[0, 1, -1, 2, -2, 2**70].each do |base|
  p [base, [0.0, -0.0, Float::NAN, -1.0, 0.5, Float::INFINITY].map { |e| (base**e).to_s }]
end
[[0, 2, 0], [0, 0, 0], [3, 2, 0], [3, -1, []], [3, 1.5, 2], [0, -1, 0], [2, 2, -3], [3, 2, 2**70], [-2, 3, 0], [3, -1, 0]].each do |a, b, m|
  p [a, b, m, a.pow(b, m)]
rescue StandardError => e
  p [a, b, m, e.class, e.message]
end
