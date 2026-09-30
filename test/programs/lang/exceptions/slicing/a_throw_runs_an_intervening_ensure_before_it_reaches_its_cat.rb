# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# `throw` runs an intervening ensure before reaching its catch.
r = catch(:t) do
  begin
    throw :t, 11
  ensure
    puts "throw-ensure"
  end
end
p r

