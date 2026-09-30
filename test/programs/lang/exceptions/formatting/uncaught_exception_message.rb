# An uncaught exception's tail format: the message, the source line, and
# the callers of the raising frame.
def boom(v)
  v.length
end

begin
  boom(nil)
rescue NoMethodError => e
  p e.message
end

p "before"
boom(nil)
