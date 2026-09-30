# An unused block parameter over an empty literal has no element type to infer
# from. The block does not run, and the call gives the receiver.
p([].each_with_index { |x, i| p i })
p([1, 2].each_with_index { |x, i| p [x, i] })
p([].each_with_index { |x, i| p x })
p([].each { |x| p x })
p([].map { |x| x })
h = {}
p(h.each_with_index { |pair, i| p i })
