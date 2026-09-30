# Symbol-keyed Hash literal + grow past the initial capacity. The grow
# must rehash correctly.
h = {x: 1}
p h[:x]

big = {}
30.times { |i| big[:"key#{i}"] = i * 3 }
p big[:key0]
p big[:key29]
p big.length
p big[:missing]
