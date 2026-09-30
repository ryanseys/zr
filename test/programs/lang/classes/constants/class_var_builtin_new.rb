# A local statically holding one builtin class constant dispatches like the
# constant itself.
k = Array
p k.new(3, 0)
h = Hash
p h.new(9)[:missing]
s = String
p s.new("ab")
k2 = Integer
p k2.name
