# Keywords at the end of an array literal make one Hash element. When
# they are only `**` splats and come out empty, no element is added.
p [1, a: 2]
p [a: 1, b: 2]
h = {}
p [**h], [1, **h]
g = {x: 1}
p [**g], [1, **g, **h]
p [1, **h, c: 3]

