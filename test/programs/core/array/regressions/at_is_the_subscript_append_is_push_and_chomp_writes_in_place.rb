# Method aliases and forms:
#   Array#at(n)      -> Array#[n]
#   Array#append(x)  -> Array#push(x), returning self (the array)
#   String#chomp!    -> changes a mutable String in place; raises
#                       FrozenError on a frozen string literal.
#                       The test uses a mutable String.

p([1, 2, 3].at(1) == 2)
p(%w[a].append("b") == %w[a b])
s = String.new("ab\n")
s.chomp!
p(s.to_s == "ab")
