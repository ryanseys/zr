# `s << int` appends the UTF-8 character with that codepoint (per
# MRI), not the decimal digits of the integer.
s = String.new("hello")
s << 33
puts s.inspect
s2 = String.new("ab")
s2 << 12354
puts s2.inspect
