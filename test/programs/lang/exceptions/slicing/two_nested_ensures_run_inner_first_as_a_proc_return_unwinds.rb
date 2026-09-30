# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# Two nested ensures run inner-first as the proc return unwinds.
def ret_through_two_ensures
  begin
    begin
      proc { return 1 }.call
    ensure
      puts "inner"
    end
  ensure
    puts "outer"
  end
  99
end
p ret_through_two_ensures

