# A `return` in a block in a class body that a lambda holds leaves the
# lambda, as ruby finds the scope at run time. zr ends only the class
# body for an inlined block, and a yielded block crashes.

def y = yield
p(-> { class Foo; 1.times { return 1 }; end; :after }.call)
p(-> { class Foo; y { return 2 }; end; :after }.call)
