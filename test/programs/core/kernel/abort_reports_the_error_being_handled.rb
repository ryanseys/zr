# abort with no message reports the error being handled, as an uncaught
# one prints, then exits 1; with a message it prints the message.
def aborting
  yield
rescue SystemExit => e
  p [e.status, e.message, e.success?]
end

aborting { abort }
aborting do
  raise "being handled"
rescue
  abort
end
aborting do
  begin
    raise ArgumentError, "the cause"
  rescue
    raise "the error"
  end
rescue
  abort
end
aborting do
  raise "handled, then a message"
rescue
  abort "own message"
end
aborting { abort "plain" }
p(begin
  abort("a", "b")
rescue ArgumentError => e
  e.message
end)
p(begin
  abort(:sym)
rescue TypeError => e
  e.message
end)
