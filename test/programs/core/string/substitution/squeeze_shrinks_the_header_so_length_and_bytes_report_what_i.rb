# String#squeeze gives a string whose length and bytes show the
# size after the squeeze, not the size before it.
s = "aaabbbccc"
result = s.squeeze
puts result.length
puts result.bytes.inspect
puts result.inspect

# The result has no trailing bytes past the squeezed text.
puts "xxxxx".squeeze.length
puts "xxxxx".squeeze
