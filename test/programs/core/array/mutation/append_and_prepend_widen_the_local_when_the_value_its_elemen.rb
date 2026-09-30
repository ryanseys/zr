# Array#append / #prepend are exact aliases for #push / #unshift. A value
# of a different kind (e.g. nil onto an Integer array) keeps its own
# value. It does not become 0.

a = [1, 2]
a.append(nil)
p a                                   #=> [1, 2, nil]

b = [1, 2]
b.prepend(nil)
p b                                   #=> [nil, 1, 2]

c = [1, 2]
c.append(3, nil)
p c                                   #=> [1, 2, 3, nil]

d = [1, 2]
d.prepend(nil, 3)
p d                                   #=> [nil, 3, 1, 2]

e = [1, 2]
e.append("x")
p e                                   #=> [1, 2, "x"]

f = [1, 2]
f.push(3, nil)
p f                                   #=> [1, 2, 3, nil]

puts "done"
