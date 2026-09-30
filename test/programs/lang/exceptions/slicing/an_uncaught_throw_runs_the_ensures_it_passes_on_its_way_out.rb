# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# An uncaught throw runs intervening ensures on its way out (it is an exception).
def uncaught_runs_ensure
  begin
    throw :gone
  ensure
    puts "uncaught-ensure"
  end
end
begin
  uncaught_runs_ensure
rescue UncaughtThrowError
  puts "rescued-uncaught"
end
