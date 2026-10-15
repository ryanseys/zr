# A bignum reads one bit at a Float index as NUM2LONG converts it: a
# truncated long, or RangeError for a Float that is no long. A fixnum
# converts the index with to_int, so it raises FloatDomainError.
def try(label)
  p [label, yield]
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

big = 2**70 + 5
indices = [0.0, 2.9, 70.5, -1.5, 1e3, 2.0**62, 2.0**63, -(2.0**63), -(2.0**63) * 2,
           -1e30, Float::INFINITY, -Float::INFINITY, Float::NAN]
indices.each do |index|
  try("big[#{index}]") { big[index] }
  try("-big[#{index}]") { (-big)[index] }
  try("5[#{index}]") { 5[index] }
end
try("big[nil]") { big[nil] }
try("5[nil]") { 5[nil] }
try("big[rational]") { big[Rational(5, 2)] }
try("big[float, 2]") { big[Float::NAN, 2] }
