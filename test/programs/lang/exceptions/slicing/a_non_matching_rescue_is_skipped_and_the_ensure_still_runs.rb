# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# A non-matching rescue is skipped; the ensure still runs.
def ret_nonmatching_rescue
  begin
    proc { return 7 }.call
  rescue TypeError
    puts "should-not-run"
  ensure
    puts "ensure-nonmatch"
  end
end
p ret_nonmatching_rescue

