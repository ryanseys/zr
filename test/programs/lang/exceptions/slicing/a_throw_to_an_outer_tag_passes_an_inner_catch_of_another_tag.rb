# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# A throw to an outer tag passes an inner catch of a different tag and runs the
# ensure between throw and the matching catch.
r2 = catch(:outer) do
  catch(:inner) do
    begin
      throw :outer, 22
    ensure
      puts "between-ensure"
    end
  end
  :inner_normal
end
p r2

