# A `return` in a block in a class body that a lambda holds leaves the
# lambda, as ruby finds the scope at run time, after the ensure clauses
# on the way. At the toplevel there is no scope to leave.
def y = yield
p(-> { class Foo; 1.times { return 1 }; end; :after }.call)
p(-> { class Foo; y { return 2 }; end; :after }.call)
p(-> { module Bar; class Baz; [1].each { return 3 }; end; end; :after }.call)
p(-> { class Foo; begin; y { return 4 }; ensure; puts "ensure"; end; end; :after }.call)
l = -> { class Foo; y { return 5 }; end; :after }
p l.call, l.call
begin
  class Foo; 1.times { return 6 }; end
rescue LocalJumpError => e
  p [e.message, e.reason]
end
p :end
