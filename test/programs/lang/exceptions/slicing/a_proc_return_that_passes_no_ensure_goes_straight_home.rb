# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# A proc return that passes through no ensure goes straight home.
def ret_no_ensure
  proc { return 5 }.call
  6
end
p ret_no_ensure

