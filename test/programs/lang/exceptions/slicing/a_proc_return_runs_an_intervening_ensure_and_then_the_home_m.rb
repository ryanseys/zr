# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# proc `return` runs an intervening ensure, then the home method returns.
def ret_through_ensure
  begin
    proc { return 30 }.call
  ensure
    puts "ensure-ret"
  end
  40
end
p ret_through_ensure

