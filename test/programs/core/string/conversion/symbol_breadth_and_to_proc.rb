# Symbol Tier A + the `&:sym` block-argument conversion
# (`Symbol#to_proc`).

p :b <=> :a
p :hello.length
p :a.succ
p :HeLLo.downcase
p :he.to_s
p :he.inspect
p :he.upcase
p :he.capitalize
p :he.empty?
p :upcase.to_proc.call("hi")
p [3, 1, 2].map(&:to_s)
p ["b", "a"].map(&:upcase)
