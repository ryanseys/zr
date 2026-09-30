# `obj.send(:raise, ...)` reaches the Kernel#raise method. It does the same
# as CRuby: class and message, bare re-raise from `$!`, a bare class that
# uses its name as the message, a String that gives a RuntimeError, and a
# TypeError for an object that is not an exception.

o = Object.new
begin
  o.send(:raise, ArgumentError, "via send")
rescue ArgumentError => e
  puts e.message
end
begin
  o.send(:raise, ArgumentError)
rescue ArgumentError => e
  puts e.message
end
begin
  o.send(:raise, "bare msg")
rescue RuntimeError => e
  puts e.message
end
begin
  o.send(:raise)
rescue RuntimeError => e
  puts "[#{e.message}]"
end
begin
  begin
    raise IOError, "orig"
  rescue
    o.send(:raise)
  end
rescue IOError => e
  puts e.message
end
begin
  o.send(:raise, 42)
rescue TypeError => e
  puts e.message
end
