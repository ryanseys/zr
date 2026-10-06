# Blockless cycle(n) on an array returns an Enumerator. to_a and first(n)
# on it give the repeated elements.
p([].cycle(2).to_a)
p([1,2].cycle(2).to_a)
p([].cycle(0).to_a)
a = [1,:b]
p a.cycle(2).to_a
p a.cycle(2).first(3)
r = []
a.cycle(2) { |x| r << x }
p r
