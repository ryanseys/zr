# A clone of a builtin class allocates what the original does: a clone
# of String makes Strings, and a clone of Array makes Arrays.
StrClone = String.clone
s = StrClone.new("ab")
p s, s.class, s.size, s == "ab", "ab" == s
p s.upcase, (s + "c")

AryClone = Array.clone
a = AryClone.new([1, 2])
p a, a.class, a.size, a.first

HashClone = Hash.clone
h = HashClone.new
h[:k] = 1
p h, h.class
