# `puts` / `print` / `printf` reached in expression context -- the
# last statement of a `proc { ... }` body. The IO side effect still
# happens.
#
# To exercise all three IO methods concisely, the test iterates an
# array of procs and `.call`s each. This also checks two more things:
#
# 1. An array literal of procs (`[proc, proc, proc]`) holds the procs.
#
# 2. `p.call` works on a block param that iterates that array, where
#    each element is a boxed proc.

[
  proc { puts "a" },
  proc { print "b\n" },
  proc { printf("c=%d\n", 3) }
].each { |p| p.call }
