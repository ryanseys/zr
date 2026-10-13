# encoding: binary
# A directive of unpack moves the position only over the bytes that it
# read, never past the end: `^` (ruby 4.1) and `X` after a short read
# see where the read stopped. A short integer read does not move it.
cases = [
  ["a", "a4^"], ["a", "A4^"], ["a\0", "Z4^"], ["a", "Z*^"], ["abc", "Z2^"],
  ["ab", "H8^"], ["ab", "h3^"], ["a", "B16^"], ["a", "b3^"], ["a", "B*^"],
  ["abc", "N^"], ["abcde", "N2^"], ["abcdefg", "n4^"], ["abc", "C5^"], ["abcdefghij", "q2^"],
  ["abcde", "e2^"], ["abcdefghij", "E2^"], ["abc", "s*^"],
  ["a", "a4X1C"], ["abcde", "N2X1C"], ["abc", "N X2 C"], ["abc", "U5^"], ["\x81", "w2^"], ["\x81", "R2^"],
  ["abc", "x^"], ["abc", "@2^"], ["abc", "a2@0^"], ["abcdef", "m^"], ["abc", "M^"], ["abc", "u^"],
  ["", "^"], ["abc", "C^C^C^C^"],
]
cases.each do |s, t|
  p [s, t, s.unpack(t)]
rescue => e
  p [s, t, e.class, e.message]
end
p "abcdef".unpack("a2^", offset: 2)
p "abcdef".unpack("a9^", offset: 2)
p "abcdef".unpack1("a9^", offset: 2)
