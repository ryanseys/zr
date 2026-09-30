# Ruby names that collide with the compiler's own vocabulary must not leak
# into the generated program: a class named after a builtin type, a method
# named after a keyword, and Ruby's `_` local, which the generated program
# has no named binding for. All are mangled on the way out, and none of the
# mangling is observable from Ruby.

# --- Ruby's `_` local ------------------------------------------------------

# `_` is an ordinary, readable local in Ruby.
_ = 10
p _
_ = _ + 5
p _

# The conventional throwaway in a block, still readable.
[[1, :a], [2, :b]].each do |n, _|
  p n
end
[[1, :a]].each { |_, sym| p sym }

# `_` in a multiple assignment.
_, second = [:first, :second]
p second
p _

# Repeated `_` params (Ruby allows the duplicate name).
[[1, 2, 3]].each { |_, _, third| p third }
