p proc { it }.parameters, lambda { it }.parameters
p proc { _1 }.parameters, lambda { _1 }.parameters
p proc { it }.arity, lambda { it }.arity
p proc { it; binding.local_variables }.call(5)
p proc { it; local_variables }.call(5)
p [1, 2].map { it * 2 }
p [[1, 2]].map { it }
p [1, 2].map { [it, [3].map { it + 1 }] }
p proc { defined?(it) }.call(1)

