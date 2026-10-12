# pack("U") converts each value to a long first (NUM2LONG), so a Bignum
# outside a long raises that RangeError, and only then checks the range
# of a code point. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

[2**64, 2**63, -2**63 - 1, 2**63 - 1, -1, 0x7fffffff, 0x80000000, 0x110000, 0x41, 2.9, "a"].each do |v|
  try("[#{v.inspect}].pack('U')") { [v].pack("U") }
end
try("U* mixed") { [0x41, 2**64].pack("U*") }
