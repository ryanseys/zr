

# `Ruby::Box.new` answers a value that IS a `Ruby::Box`.
#
# `b.class.to_s` answers "Ruby::Box", and `b.is_a?(Ruby::Box)` is
# true. `b.eval` resolves `Ruby::Box#eval`, not `Kernel#eval`.
#
# `Ruby::Box.new` needs `RUBY_BOX=1` in the environment when the
# program RUNS, not when it compiles.

b = Ruby::Box.new
p b.class.to_s
p b.is_a?(Ruby::Box)
p b.main?
