# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# proc return passing through a rescue modifier still returns home.
def ret_through_rescue_modifier
  x = (proc { return 9 }.call rescue 0)
  x + 100
end
p ret_through_rescue_modifier

