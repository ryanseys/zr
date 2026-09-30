# A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
# `ensure` blocks it passes over before delivering, like an exception. An
# uncaught `throw` raises a (catchable) UncaughtThrowError.

# An uncaught throw raises UncaughtThrowError -- catchable by its class and by a
# bare rescue (it is a StandardError), with a CRuby-shaped message.
begin
  throw :nope
rescue UncaughtThrowError => e
  puts e.message
end

begin
  throw :nope, 1
rescue => e
  puts "bare: #{e.message}"
end

