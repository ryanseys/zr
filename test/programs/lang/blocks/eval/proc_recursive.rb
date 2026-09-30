# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# A proc reaching itself through a captured local.
# At exit: cycle leak: 4 objects (Proc x2, cell x2)
# A proc/lambda that refers to its own binding recurses through the
# captured cell. Each body has a single recursive `.call` per expression;
# two poly-returning proc calls in one expression (e.g. naive fib) instead
# exercise the shared poly-return slot, an orthogonal limitation.
fact = proc { |n| n <= 1 ? 1 : n * fact.call(n - 1) }
p fact.call(5)

f = ->(n) { n <= 1 ? 1 : n * f.call(n - 1) }
p f.call(6)
