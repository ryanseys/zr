# String#chomp! on a mutable String changes the receiver in place.
# Frozen string literals raise FrozenError.
s = String.new("hello\n")
s.chomp!
puts s.to_s

s2 = String.new("hi\r\n")
s2.chomp!
puts s2.to_s

# upcase! / downcase! / strip! / lstrip! / rstrip! also mutate.
u = String.new("abc")
u.upcase!
puts u.to_s

t = String.new("  spaces  ")
t.strip!
puts t.to_s
