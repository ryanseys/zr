# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# A normal exception still runs its ensure.
def raise_through_ensure
  begin
    raise "boom"
  ensure
    puts "exc-ensure"
  end
end
begin
  raise_through_ensure
rescue => e
  puts "caught: #{e.message}"
end

