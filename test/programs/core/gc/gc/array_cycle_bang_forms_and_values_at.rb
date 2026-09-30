p [1, 2, 3].cycle(2).to_a
c = []
[1, 2].cycle(2) { |x| c << x }
p c
p [1, 2].cycle(0).to_a
p [[1, [2, 3]], [4]].flatten!
a = [1, 2]
p a.flatten!
b = [3, 1, 2]
b.sort_by! { |x| -x }
p b
p [1, 2, 3].values_at(0, 2, 5)
p [1, 2, 3].values_at(0..1)
p [1, 2, 3, 4, 5].values_at(3..9)
