# Which CLASS owns a builtin method is part of its behaviour, not a detail of
# reflection: it decides which receivers answer it. This locks the boundaries
# the arity census proved zr had drawn in the wrong place.

require "pathname"
require "tmpdir"

def owner_of(klass, name)
  klass.instance_method(name).owner
rescue NameError
  "absent"
end

# The bound is SizedQueue's; an unbounded Queue has no `max` at all.
puts "-- SizedQueue, not Queue"
q = Thread::Queue.new
[:max, :max=].each do |m|
  begin
    m == :max ? q.max : (q.max = 1)
  rescue NoMethodError
    puts "Queue##{m}: NoMethodError"
  end
end
s = Thread::SizedQueue.new(2)
p s.max
s.max = 5
p s.max

